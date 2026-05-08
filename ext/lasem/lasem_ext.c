#include <ruby.h>
#include <ruby/encoding.h>

#include <cairo-pdf.h>
#include <cairo-ps.h>
#include <cairo-svg.h>
#include <glib-object.h>
#include <math.h>
#include <limits.h>
#include <string.h>

/* Lasem: core DOM and parser APIs used to parse SVG, MathML, and itex input. */
#include <lsm.h>
#include <lsmdomparser.h>
#include <lsmmathmldocument.h>

static VALUE m_lasem;
static VALUE m_native;
static VALUE e_error;
static VALUE e_dependency_error;
static VALUE e_render_error;

static VALUE
lasem_get_or_define_class(VALUE parent, const char *name, VALUE superclass)
{
	ID id = rb_intern(name);

	if (rb_const_defined_at(parent, id)) {
		return rb_const_get(parent, id);
	}

	return rb_define_class_under(parent, name, superclass);
}

static void
lasem_raise_gerror(VALUE error_class, GError *error, const char *fallback_message)
{
	if (error != NULL) {
		VALUE message = rb_str_new_cstr(error->message);
		g_error_free(error);
		rb_exc_raise(rb_exc_new_str(error_class, message));
	}

	rb_raise(error_class, "%s", fallback_message);
}

static cairo_status_t
lasem_write_to_ruby_string(void *closure, const unsigned char *data, unsigned int length)
{
	VALUE *output = (VALUE *) closure;

	rb_str_cat(*output, (const char *) data, length);
	return CAIRO_STATUS_SUCCESS;
}

static unsigned int
lasem_positive_pixel_size(double value, const char *name)
{
	if (!isfinite(value) || value <= 0.0) {
		rb_raise(e_render_error, "%s must be greater than 0", name);
	}

	if (value > UINT_MAX) {
		rb_raise(e_render_error, "%s is too large", name);
	}

	return (unsigned int) ceil(value);
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
lasem_create_surface(const char *format, VALUE *output, double width_pt, double height_pt,
		     unsigned int width_px, unsigned int height_px)
{
	if (strcmp(format, "svg") == 0) {
		/* Cairo: vector SVG output is streamed into a Ruby string callback. */
		return cairo_svg_surface_create_for_stream(lasem_write_to_ruby_string, output, width_pt, height_pt);
	}

	if (strcmp(format, "pdf") == 0) {
		/* Cairo: vector PDF output is streamed into a Ruby string callback. */
		return cairo_pdf_surface_create_for_stream(lasem_write_to_ruby_string, output, width_pt, height_pt);
	}

	if (strcmp(format, "ps") == 0) {
		/* Cairo: vector PostScript output is streamed into a Ruby string callback. */
		return cairo_ps_surface_create_for_stream(lasem_write_to_ruby_string, output, width_pt, height_pt);
	}

	if (strcmp(format, "png") == 0) {
		/* Cairo: raster PNG output is rendered through an ARGB image surface. */
		return cairo_image_surface_create(CAIRO_FORMAT_ARGB32, width_px, height_px);
	}

	rb_raise(e_render_error, "unsupported output format: %s", format);
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
	unsigned int width_px;
	unsigned int height_px;
	int explicit_size;

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
	explicit_size = !NIL_P(width_value) && !NIL_P(height_value);

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

	width_pt = 2.0;
	height_pt = 2.0;
	lsm_dom_view_get_size(view, &width_pt, &height_pt, NULL);
	lsm_dom_view_get_size_pixels(view, &width_px, &height_px, NULL);

	if (explicit_size) {
		width_pt = NUM2DBL(width_value);
		height_pt = NUM2DBL(height_value);
		width_px = lasem_positive_pixel_size(width_pt, "width");
		height_px = lasem_positive_pixel_size(height_pt, "height");
	} else {
		width_pt *= zoom;
		height_pt *= zoom;
		width_px = lasem_positive_pixel_size((double) width_px * zoom, "width");
		height_px = lasem_positive_pixel_size((double) height_px * zoom, "height");
	}

	output = rb_str_new(NULL, 0);
	rb_enc_associate_index(output, rb_ascii8bit_encindex());

	surface = lasem_create_surface(format, &output, width_pt, height_pt, width_px, height_px);
	status = cairo_surface_status(surface);
	if (status != CAIRO_STATUS_SUCCESS) {
		g_object_unref(view);
		g_object_unref(document);
		rb_raise(e_render_error, "Cairo could not create a rendering surface: %s",
			 cairo_status_to_string(status));
	}

	cairo = cairo_create(surface);
	cairo_scale(cairo, zoom, zoom);
	lsm_dom_view_render(view, cairo, -offset_x, -offset_y);

	status = cairo_status(cairo);
	if (status != CAIRO_STATUS_SUCCESS) {
		cairo_destroy(cairo);
		cairo_surface_destroy(surface);
		g_object_unref(view);
		g_object_unref(document);
		rb_raise(e_render_error, "Cairo rendering failed: %s", cairo_status_to_string(status));
	}

	if (strcmp(format, "png") == 0) {
		status = cairo_surface_write_to_png_stream(cairo_get_target(cairo),
							   lasem_write_to_ruby_string,
							   &output);
		if (status != CAIRO_STATUS_SUCCESS) {
			cairo_destroy(cairo);
			cairo_surface_destroy(surface);
			g_object_unref(view);
			g_object_unref(document);
			rb_raise(e_render_error, "Cairo PNG output failed: %s", cairo_status_to_string(status));
		}
	}

	cairo_destroy(cairo);
	cairo_surface_finish(surface);
	status = cairo_surface_status(surface);
	cairo_surface_destroy(surface);
	g_object_unref(view);
	g_object_unref(document);

	if (status != CAIRO_STATUS_SUCCESS) {
		rb_raise(e_render_error, "Cairo output failed: %s", cairo_status_to_string(status));
	}

	RB_GC_GUARD(output);
	return output;
}

void
Init_lasem(void)
{
	m_lasem = rb_define_module("Lasem");
	m_native = rb_define_module_under(m_lasem, "Native");
	e_error = lasem_get_or_define_class(m_lasem, "Error", rb_eStandardError);
	e_dependency_error = lasem_get_or_define_class(m_lasem, "DependencyError", e_error);
	e_render_error = lasem_get_or_define_class(m_lasem, "RenderError", e_error);

	rb_define_singleton_method(m_native, "native_available?", lasem_native_available, 0);
	rb_define_singleton_method(m_native, "render", lasem_native_render, 9);
}
