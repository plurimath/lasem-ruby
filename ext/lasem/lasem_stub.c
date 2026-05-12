#include <ruby.h>

static VALUE
lasem_get_or_define_class(VALUE parent, const char *name, VALUE superclass)
{
	ID id = rb_intern(name);

	if (rb_const_defined_at(parent, id)) {
		return rb_const_get(parent, id);
	}

	return rb_define_class_under(parent, name, superclass);
}

static VALUE
lasem_native_available(VALUE self)
{
	return Qfalse;
}

static VALUE
lasem_native_render(int argc, VALUE *argv, VALUE self)
{
	VALUE m_lasem = rb_define_module("Lasem");
	VALUE e_error = lasem_get_or_define_class(m_lasem, "Error", rb_eStandardError);
	VALUE e_dependency_error = lasem_get_or_define_class(m_lasem, "DependencyError", e_error);

	/* Keep in sync with Lasem::DependencyError::MESSAGE. */
	rb_raise(e_dependency_error,
		 "Lasem native library is not available. Install a system "
		 "Lasem development package, then rebuild the gem. Run "
		 "`lasem-doctor --all-warnings` or `bundle exec rake "
		 "lasem:doctor WARNINGS=all` for setup diagnostics.");
	return Qnil;
}

void
Init_lasem(void)
{
	VALUE m_lasem = rb_define_module("Lasem");
	VALUE m_native = rb_define_module_under(m_lasem, "Native");

	rb_define_singleton_method(m_native, "native_available?", lasem_native_available, 0);
	rb_define_singleton_method(m_native, "render", lasem_native_render, -1);
}
