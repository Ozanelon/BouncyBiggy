extends Control

const SHEETS_URL = "https://script.google.com/macros/s/AKfycby3e8qp5wN7QyqGJo0eHRumcgSnoJoJd48ZF6I41kBYx9jeTwJOjvKX50YBBhh7f-LZ/exec"
const VARSAYILAN_ISIM := "İsimsiz"
const MAX_ISIM_UZUNLUGU := 20
const ISTEK_ZAMAN_ASIMI := 10.0  # saniye

@onready var isim_sorucu: AcceptDialog = $isim
@onready var line_edit: LineEdit = $isim/LineEdit

@onready var skor_penceresi: AcceptDialog = $SkorPenceresi
@onready var liste_label: RichTextLabel = $SkorPenceresi/RichTextLabel

var gonderiliyor := false


func _ready() -> void:

	process_mode = Node.PROCESS_MODE_ALWAYS

	liste_label.bbcode_enabled = true
	line_edit.max_length = MAX_ISIM_UZUNLUGU

	skor_penceresi.hide()
	isim_sorucu.hide()


	isim_sorucu.confirmed.connect(_on_isim_girildi)
	isim_sorucu.canceled.connect(_menuyu_geri_getir)


	skor_penceresi.visibility_changed.connect(_on_skor_penceresi_visibility_changed)


func _menuyu_geri_getir() -> void:
	visible = true


func _on_skor_penceresi_visibility_changed() -> void:
	if not skor_penceresi.visible:
		visible = true


func _on_devam_et_pressed() -> void:
	get_tree().paused = false
	visible = false


func _on_çıkış_pressed() -> void:

	visible = false
	isim_sorucu.popup_centered()



func _on_isim_girildi() -> void:
	if gonderiliyor:
		return

	var oyuncu_adi := line_edit.text.strip_edges()
	if oyuncu_adi == "":
		oyuncu_adi = VARSAYILAN_ISIM


	var skor := 0
	var sahne := get_tree().current_scene
	if sahne != null and "mevcut_asama" in sahne:
		skor = int(sahne.mevcut_asama)
	else:
		push_warning("Ana sahnede 'mevcut_asama' değişkeni bulunamadı, skor 0 gönderiliyor.")

	print("Gönderiliyor -> Oyuncu: ", oyuncu_adi, " | Skor: ", skor)
	skoru_gonder(oyuncu_adi, skor)


func skoru_gonder(isim: String, skor: int) -> void:
	gonderiliyor = true

	var http := HTTPRequest.new()
	http.timeout = ISTEK_ZAMAN_ASIMI


	http.max_redirects = 0
	add_child(http)
	http.request_completed.connect(_on_skor_gonderildi.bind(http))

	var headers := ["Content-Type: application/json"]
	var body := JSON.stringify({"isim": isim, "skor": skor})
	var err := http.request(SHEETS_URL, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		print("HTTP İsteği Başlatılamadı! Hata: ", err)
		http.queue_free()
		get_tree().quit()


func _on_skor_gonderildi(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	print("Sunucu Yanıtı -> Result: ", result, " | HTTP Kodu: ", response_code)

	if response_code in [200, 301, 302, 303]:
		print("Skor başarıyla gönderildi.")
	else:
		print("Skor gönderilemedi! Cevap: ", body.get_string_from_utf8().left(200))

	http.queue_free()
	get_tree().quit()


func _on_skor_tablosu_pressed() -> void:


	visible = false
	skor_penceresi.title = "Skor Tablosu"
	skor_penceresi.popup_centered(Vector2i(400, 300))
	liste_label.text = "Skorlar yükleniyor..."

	var http := HTTPRequest.new()
	http.timeout = ISTEK_ZAMAN_ASIMI
	add_child(http)
	http.request_completed.connect(_on_skorlar_geldi.bind(http))

	var err := http.request(SHEETS_URL)
	if err != OK:
		liste_label.text = "Skorlar yüklenemedi!"
		print("HTTP İsteği Başlatılamadı! Hata: ", err)
		http.queue_free()


func _on_skorlar_geldi(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	http.queue_free()

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		liste_label.text = "Skorlar yüklenemedi!"
		print("Skorlar yüklenemedi! Result: ", result, " | HTTP Kodu: ", response_code)
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or typeof(json.data) != TYPE_ARRAY:
		liste_label.text = "Skor verisi okunamadı!"
		return


	var skor_listesi: Array = (json.data as Array).filter(func(k): return k is Dictionary)


	skor_listesi.sort_custom(func(a, b): return int(a.get("skor", 0)) > int(b.get("skor", 0)))

	var metin := "[b]Sıra  |  İsim  |  Skor[/b]\n"
	metin += "--------------------------------\n"

	for i in range(min(10, skor_listesi.size())):  # İlk 10
		var kayit: Dictionary = skor_listesi[i]
		var isim := str(kayit.get("isim", "?")).replace("[", "[lb]") 
		var skor := str(kayit.get("skor", 0))
		metin += "%d.    %s    (Aşama: %s)\n" % [i + 1, isim, skor]

	liste_label.text = metin
	print("--- SKOR TABLOSU GÜNCELLENDİ ---")
