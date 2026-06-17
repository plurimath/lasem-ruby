#include <ruby.h>
#include <ruby/encoding.h>

#include <cairo-pdf.h>
#include <cairo-ps.h>
#include <cairo-svg.h>
#include <glib-object.h>
#include <math.h>
#include <limits.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

/* Lasem: core DOM and parser APIs used to parse SVG, MathML, and itex input. */
#include <lsm.h>
#include <lsmdomparser.h>
#include <lsmmathmldocument.h>

/* Upper bound on total raster (ARGB32) pixels, to keep a single render from
 * allocating unbounded memory when fed untrusted input. The default ~= 256 MB
 * (4 bytes/pixel). Override at build time with -DLASEM_MAX_RASTER_PIXELS=N. */
#ifndef LASEM_MAX_RASTER_PIXELS
#define LASEM_MAX_RASTER_PIXELS (64ULL * 1024ULL * 1024ULL)
#endif

static VALUE m_lasem;
static VALUE m_native;
static VALUE e_render_error;

/* Keep in sync with lib/lasem/error.rb: Lasem::Error is a marker MODULE mixed
 * into every gem error so `rescue Lasem::Error` catches them all, while each
 * error keeps its own superclass (e.g. OptionError stays an ArgumentError). */
static VALUE
lasem_get_or_define_module(VALUE parent, const char *name)
{
	ID id = rb_intern(name);

	if (rb_const_defined_at(parent, id)) {
		return rb_const_get(parent, id);
	}

	return rb_define_module_under(parent, name);
}

/* Define (or fetch) a StandardError subclass under `parent` and include the
 * Lasem::Error marker module so the error is rescuable both as itself and as
 * Lasem::Error. Tolerant of the class already existing (Ruby autoload order). */
static VALUE
lasem_define_error_class(VALUE parent, const char *name, VALUE marker)
{
	ID id = rb_intern(name);
	VALUE klass;

	if (rb_const_defined_at(parent, id)) {
		klass = rb_const_get(parent, id);
	} else {
		klass = rb_define_class_under(parent, name, rb_eStandardError);
	}

	rb_include_module(klass, marker);
	return klass;
}

static void
lasem_raise_gerror(VALUE error_class, GError *error, const char *fallback_message)
{
	if (error != NULL) {
		/* Copy the message onto the stack and free the GError before any Ruby
		 * allocation, so a raising allocation cannot leak the GError. */
		char message[512];

		g_strlcpy(message, error->message, sizeof(message));
		g_error_free(error);
		rb_raise(error_class, "%s", message);
	}

	rb_raise(error_class, "%s", fallback_message);
}

/* Growable C byte buffer used to collect Cairo output. The Ruby result string
 * is built from it only after every native resource is released, so the Cairo
 * write callback never calls into the Ruby runtime (where an allocation could
 * raise and longjmp out, leaking the surface/context/view/document). */
typedef struct {
	unsigned char *data;
	size_t length;
	size_t capacity;
	int failed;
} lasem_buffer;

static cairo_status_t
lasem_buffer_write(void *closure, const unsigned char *data, unsigned int length)
{
	lasem_buffer *buffer = (lasem_buffer *) closure;
	size_t needed;

	if (buffer->failed) {
		return CAIRO_STATUS_WRITE_ERROR;
	}

	needed = buffer->length + length;
	if (needed < buffer->length) {
		/* size_t overflow */
		buffer->failed = 1;
		return CAIRO_STATUS_WRITE_ERROR;
	}

	if (needed > buffer->capacity) {
		size_t capacity = buffer->capacity ? buffer->capacity : 4096;
		unsigned char *grown;

		while (capacity < needed) {
			if (capacity > SIZE_MAX / 2) {
				capacity = needed;
				break;
			}
			capacity *= 2;
		}

		grown = realloc(buffer->data, capacity);
		if (grown == NULL) {
			buffer->failed = 1;
			return CAIRO_STATUS_WRITE_ERROR;
		}

		buffer->data = grown;
		buffer->capacity = capacity;
	}

	memcpy(buffer->data + buffer->length, data, length);
	buffer->length += length;
	return CAIRO_STATUS_SUCCESS;
}

struct lasem_string_build {
	const char *data;
	long length;
};

/* Runs under rb_protect so the caller can free the C buffer even if this
 * (Ruby) allocation raises. */
static VALUE
lasem_build_output_string(VALUE arg)
{
	struct lasem_string_build *build = (struct lasem_string_build *) arg;
	VALUE string = rb_str_new(build->data, build->length);

	rb_enc_associate_index(string, rb_ascii8bit_encindex());
	return string;
}

static int
lasem_positive_pixel_size(double value, unsigned int *size, const char **message)
{
	if (!isfinite(value) || value <= 0.0) {
		*message = "must be greater than 0";
		return 0;
	}

	if (value > INT_MAX) {
		*message = "is too large";
		return 0;
	}

	*size = (unsigned int) ceil(value);
	return 1;
}

static unsigned int
lasem_checked_positive_pixel_size(double value, const char *name)
{
	unsigned int size;
	const char *message;

	if (!lasem_positive_pixel_size(value, &size, &message)) {
		rb_raise(e_render_error, "%s %s", name, message);
	}

	return size;
}

/* Reject raster surfaces whose total pixel count would exceed the configured
 * budget, guarding against OOM from hostile or pathological input. */
static int
lasem_raster_budget_ok(unsigned int width_px, unsigned int height_px)
{
	return (uint64_t) width_px * (uint64_t) height_px <= LASEM_MAX_RASTER_PIXELS;
}

static int
lasem_supported_output_format(const char *format)
{
	return strcmp(format, "svg") == 0 ||
	       strcmp(format, "pdf") == 0 ||
	       strcmp(format, "ps") == 0 ||
	       strcmp(format, "png") == 0;
}

static LsmDomDocument *
lasem_document_from_input(const char *input, gssize input_size, const char *input_type, GError **error)
{
	if (strcmp(input_type, "latex") == 0 || strcmp(input_type, "itex") == 0) {
		/* Lasem: itex parser accepts TeX-like math input and returns a MathML document. */
		return LSM_DOM_DOCUMENT(lsm_mathml_document_new_from_itex(input, input_size, error));
	}

	/* Lasem: XML parser accepts SVG or MathML documents from memory. */
	return lsm_dom_document_new_from_memory(input, input_size, error);
}

static cairo_surface_t *
lasem_create_surface(const char *format, lasem_buffer *buffer, double width_pt, double height_pt,
		     unsigned int width_px, unsigned int height_px)
{
	if (strcmp(format, "svg") == 0) {
		/* Cairo: vector SVG output is streamed into the C byte buffer. */
		return cairo_svg_surface_create_for_stream(lasem_buffer_write, buffer, width_pt, height_pt);
	}

	if (strcmp(format, "pdf") == 0) {
		/* Cairo: vector PDF output is streamed into the C byte buffer. */
		return cairo_pdf_surface_create_for_stream(lasem_buffer_write, buffer, width_pt, height_pt);
	}

	if (strcmp(format, "ps") == 0) {
		/* Cairo: vector PostScript output is streamed into the C byte buffer. */
		return cairo_ps_surface_create_for_stream(lasem_buffer_write, buffer, width_pt, height_pt);
	}

	if (strcmp(format, "png") == 0) {
		/* Cairo: raster PNG output is rendered through an ARGB image surface. */
		return cairo_image_surface_create(CAIRO_FORMAT_ARGB32, (int) width_px, (int) height_px);
	}

	return NULL;
}

static VALUE
lasem_native_available(VALUE self)
{
	return Qtrue;
}

static VALUE
lasem_native_render(VALUE self, VALUE input_value, VALUE input_type_value, VALUE format_value,
		    VALUE ppi_value, VALUE zoom_value, VALUE width_value, VALUE height_value,
		    VALUE offset_x_value, VALUE offset_y_value)
{
	GError *error = NULL;
	/* Lasem: parsed input document, either XML-backed or generated from itex. */
	LsmDomDocument *document;
	/* Lasem: layout/rendering view created from the parsed document. */
	LsmDomView *view;
	/* Cairo: target surface and drawing context for the requested output format. */
	cairo_surface_t *surface;
	cairo_t *cairo;
	cairo_status_t status;
	lasem_buffer buffer = { NULL, 0, 0, 0 };
	VALUE output;
	const char *input;
	const char *input_type;
	const char *format;
	gssize input_size;
	double ppi;
	double zoom;
	double width_pt;
	double height_pt;
	double offset_x;
	double offset_y;
	double render_offset_x;
	double render_offset_y;
	unsigned int width_px = 0;
	unsigned int height_px = 0;
	int explicit_size;
	int raster_output;
	const char *pixel_size_error;

	StringValue(input_value);
	StringValue(input_type_value);
	StringValue(format_value);

	input = RSTRING_PTR(input_value);
	input_size = (gssize) RSTRING_LEN(input_value);
	input_type = StringValueCStr(input_type_value);
	format = StringValueCStr(format_value);
	ppi = NUM2DBL(ppi_value);
	zoom = NUM2DBL(zoom_value);
	offset_x = NUM2DBL(offset_x_value);
	offset_y = NUM2DBL(offset_y_value);
	render_offset_x = zoom * offset_x;
	render_offset_y = zoom * offset_y;
	explicit_size = !NIL_P(width_value) && !NIL_P(height_value);
	raster_output = strcmp(format, "png") == 0;
	/* Defense in depth: Lasem::RenderOptions already validates these, but
	 * Native.render is a public entry point, so re-check before doing any work. */
	if (!isfinite(ppi) || ppi <= 0.0) {
		rb_raise(e_render_error, "ppi must be greater than 0");
	}
	if (!isfinite(zoom) || zoom <= 0.0) {
		rb_raise(e_render_error, "zoom must be greater than 0");
	}
	if (!isfinite(offset_x) || !isfinite(offset_y)) {
		rb_raise(e_render_error, "offset must be finite");
	}
	if (!lasem_supported_output_format(format)) {
		rb_raise(e_render_error, "unsupported output format: %s", format);
	}
	if (explicit_size) {
		width_pt = zoom * NUM2DBL(width_value);
		height_pt = zoom * NUM2DBL(height_value);
		if (raster_output) {
			width_px = lasem_checked_positive_pixel_size(width_pt * ppi / 72.0, "width");
			height_px = lasem_checked_positive_pixel_size(height_pt * ppi / 72.0, "height");
			if (!lasem_raster_budget_ok(width_px, height_px)) {
				rb_raise(e_render_error,
					 "requested raster size %ux%u exceeds the maximum of %llu pixels",
					 width_px, height_px,
					 (unsigned long long) LASEM_MAX_RASTER_PIXELS);
			}
		}
	}

	/* The GVL is deliberately held for the whole parse/layout/render. Lasem's
	 * XML parser and Pango/fontconfig are not guaranteed thread-safe, so the
	 * GVL is what serializes concurrent renders in one process. Do NOT wrap
	 * this in rb_thread_call_without_gvl without first making upstream Lasem
	 * usage thread-safe (e.g. a process-wide mutex). */
	document = lasem_document_from_input(input, input_size, input_type, &error);
	if (document == NULL) {
		lasem_raise_gerror(e_render_error, error, "Lasem could not parse the input document");
	}

	view = lsm_dom_document_create_view(document);
	if (view == NULL) {
		g_object_unref(document);
		rb_raise(e_render_error, "Lasem could not create a rendering view");
	}

	lsm_dom_view_set_resolution(view, ppi);

	if (!explicit_size) {
		width_pt = 2.0;
		height_pt = 2.0;
		lsm_dom_view_get_size(view, &width_pt, &height_pt, NULL);
		width_pt *= zoom;
		height_pt *= zoom;
		if (raster_output) {
			lsm_dom_view_get_size_pixels(view, &width_px, &height_px, NULL);
			if (!lasem_positive_pixel_size((double) width_px * zoom, &width_px, &pixel_size_error)) {
				g_object_unref(view);
				g_object_unref(document);
				rb_raise(e_render_error, "width %s", pixel_size_error);
			}
			if (!lasem_positive_pixel_size((double) height_px * zoom, &height_px, &pixel_size_error)) {
				g_object_unref(view);
				g_object_unref(document);
				rb_raise(e_render_error, "height %s", pixel_size_error);
			}
			if (!lasem_raster_budget_ok(width_px, height_px)) {
				g_object_unref(view);
				g_object_unref(document);
				rb_raise(e_render_error,
					 "rendered raster size %ux%u exceeds the maximum of %llu pixels",
					 width_px, height_px,
					 (unsigned long long) LASEM_MAX_RASTER_PIXELS);
			}
		}
	}

	surface = lasem_create_surface(format, &buffer, width_pt, height_pt, width_px, height_px);
	if (surface == NULL) {
		g_object_unref(view);
		g_object_unref(document);
		rb_raise(e_render_error, "Cairo could not allocate a rendering surface");
	}
	status = cairo_surface_status(surface);
	if (status != CAIRO_STATUS_SUCCESS) {
		cairo_surface_destroy(surface);
		g_object_unref(view);
		g_object_unref(document);
		rb_raise(e_render_error, "Cairo could not create a rendering surface: %s",
			 cairo_status_to_string(status));
	}

	cairo = cairo_create(surface);
	cairo_scale(cairo, zoom, zoom);
	lsm_dom_view_render(view, cairo, -render_offset_x, -render_offset_y);

	status = cairo_status(cairo);
	if (status != CAIRO_STATUS_SUCCESS) {
		cairo_destroy(cairo);
		cairo_surface_destroy(surface);
		g_object_unref(view);
		g_object_unref(document);
		free(buffer.data);
		rb_raise(e_render_error, "Cairo rendering failed: %s", cairo_status_to_string(status));
	}

	if (raster_output) {
		status = cairo_surface_write_to_png_stream(cairo_get_target(cairo),
							   lasem_buffer_write,
							   &buffer);
		if (status != CAIRO_STATUS_SUCCESS) {
			cairo_destroy(cairo);
			cairo_surface_destroy(surface);
			g_object_unref(view);
			g_object_unref(document);
			free(buffer.data);
			rb_raise(e_render_error, "Cairo PNG output failed: %s", cairo_status_to_string(status));
		}
	}

	cairo_destroy(cairo);
	cairo_surface_finish(surface);
	status = cairo_surface_status(surface);
	cairo_surface_destroy(surface);
	g_object_unref(view);
	g_object_unref(document);

	/* All native resources are now released. Build the Ruby string last so a
	 * Ruby allocation that raises cannot longjmp past the cleanup above. */
	if (buffer.failed) {
		free(buffer.data);
		rb_raise(e_render_error, "out of memory while collecting rendered output");
	}
	if (status != CAIRO_STATUS_SUCCESS) {
		free(buffer.data);
		rb_raise(e_render_error, "Cairo output failed: %s", cairo_status_to_string(status));
	}

	if (buffer.length > (size_t) LONG_MAX) {
		free(buffer.data);
		rb_raise(e_render_error, "rendered output is too large");
	}

	{
		struct lasem_string_build build = {
			(const char *) buffer.data,
			(long) buffer.length,
		};
		int state = 0;

		/* Build the Ruby string under rb_protect so buffer.data is freed even
		 * if the allocation raises (e.g. on memory pressure). */
		output = rb_protect(lasem_build_output_string, (VALUE) &build, &state);
		free(buffer.data);
		buffer.data = NULL;
		if (state) {
			rb_jump_tag(state);
		}
	}

	RB_GC_GUARD(output);
	return output;
}

void
Init_lasem(void)
{
	VALUE e_error;

	m_lasem = rb_define_module("Lasem");
	m_native = rb_define_module_under(m_lasem, "Native");
	e_error = lasem_get_or_define_module(m_lasem, "Error");
	lasem_define_error_class(m_lasem, "DependencyError", e_error);
	e_render_error = lasem_define_error_class(m_lasem, "RenderError", e_error);

	rb_define_singleton_method(m_native, "native_available?", lasem_native_available, 0);
	rb_define_singleton_method(m_native, "render", lasem_native_render, 9);
}
