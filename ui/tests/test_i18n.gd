extends TestCase
## Idioma de la UI: los textos fuente están en español y `i18n/en.po` los
## traduce al inglés.

const MAIN := preload("res://main.gd")
const INSTALL_DIALOG := preload("res://dialogs/install_dialog.gd")


func after_each() -> void:
	TranslationServer.set_locale("es")


func test_locale_from_os_language() -> void:
	assert_eq(MAIN.ui_locale("es"), "es")
	assert_eq(MAIN.ui_locale("en"), "en")
	assert_eq(MAIN.ui_locale("de"), "en", "otro idioma: inglés")
	assert_eq(MAIN.ui_locale(""), "en")


func test_english_translation() -> void:
	TranslationServer.set_locale("en")
	assert_eq(String(TranslationServer.translate("Proyectos")), "Projects")
	assert_eq(String(TranslationServer.translate("%s · fijada")) % "4.3-stable", "4.3-stable · pinned")
	assert_eq(INSTALL_DIALOG.title_for(_options(true)), "Installing 4.8-beta3 (mono)")


func test_spanish_is_the_source() -> void:
	TranslationServer.set_locale("es")
	assert_eq(String(TranslationServer.translate("Proyectos")), "Proyectos")
	assert_eq(INSTALL_DIALOG.title_for(_options(true)), "Instalando 4.8-beta3 (mono)")


func _options(mono: bool) -> InstallOptions:
	var o := InstallOptions.new()
	o.version = "4.8-beta3"
	o.mono = mono
	return o
