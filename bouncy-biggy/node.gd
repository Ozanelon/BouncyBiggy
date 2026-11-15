extends Node2D

@onready var main = $"."
@onready var pause_menu = $CanvasLayer2/PauseMenu

@onready var top: RigidBody2D = $RigidBody2D
@onready var top_gorsel: Sprite2D = $RigidBody2D/Sprite2D
@onready var delik_sablon: Node2D = $delik
@onready var asama_label: Label = $CanvasLayer/Label
@onready var yon_cizgisi: Line2D = $Line2D

# sesler
var hit_sesi: AudioStreamPlayer
var laser_sesi: AudioStreamPlayer

# ayarlar
const HIZ: float = 1500.0
const MAKS_SEKME_SAYISI: int = 4         # Sadece nişan çizgisi ve seviye üretimi için
const TOP_YARICAPI: float = 16.0
const RAY_UZUNLUGU: float = 1500.0
const EK_MESAFE: float = 120.0             # Nişan çizgisinin son sekmeden sonraki uzunluğu
const MIN_NISAN_MESAFESI: float = 10.0
const ASAMA_GECIS_SURESI: float = 0.2      # Animasyondan sonraki kısa bekleme
const KAYBOLMA_SURESI: float = 0.35        # Top deliğe girip kaybolma animasyonu
const MAKS_ADIM_PER_KARE: int = 16         # Köşede sonsuz döngüye girmesin diye

# delik pozisyon
const MIN_TOP_DELIK_MESAFESI: float = 150.0  # Top ile delik arası minimum mesafe
const MIN_DELIK_ARASI: float = 120.0         # İki delik arası minimum mesafe
const MAKS_URETIM_DENEMESI: int = 60         # Çözülebilir seviye bulmak için deneme sayısı
const ADAY_DENEMESI: int = 150               # Bir atış yolunda delik noktası arama sayısı

# aşamalarda delikler [aşama, delik sayısı]
const DELIK_KADEMELERI: Array = [
	[45, 7],
	[30, 6],
	[19, 5],
	[13, 4],
	[6, 3],
	[3, 2],
	[1, 1],
]

const MIN_X: float = -350.0
const MAX_X: float = 350.0
const MIN_Y: float = -100.0
const MAX_Y: float = 100.0

@export var delik_yakalama_mesafesi: float = 40.0
@export var maks_atis_suresi: float = 7.0         # Top atıştan sonra bu kadar saniye hareket eder
@export var yakalama_alanini_goster: bool = false  # Hata ayıklama: kırmızı daire

# durum
var mevcut_asama: int = 1
var top_firlatildi: bool = false
var seviye_geciriliyor: bool = true  # İlk fizik karesi gelene kadar giriş kapalı
var top_baslangic_konumu: Vector2 = Vector2.ZERO
var top_yon: Vector2 = Vector2.ZERO
var atis_suresi_kalan: float = 0.0

var top_gorsel_olcek: Vector2 = Vector2.ONE
var top_gorsel_rotasyon: float = 0.0

var delikler: Array[Node2D] = []
var delik_gorselleri: Array[Sprite2D] = []
var delik_alindi: Array[bool] = []


func _ready() -> void:
	pause_menu.visible = false
	
	top.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	top.freeze = true

	# sesi sahneye ekleme
	hit_sesi = AudioStreamPlayer.new()
	hit_sesi.stream = load("res://ses/hitHurt.wav")
	add_child(hit_sesi)

	laser_sesi = AudioStreamPlayer.new()
	laser_sesi.stream = load("res://ses/random.wav")
	add_child(laser_sesi)

	# görsel orijinal değerler (animasyon için)
	top_gorsel_olcek = top_gorsel.scale
	top_gorsel_rotasyon = top_gorsel.rotation

	delik_sablon.visible = false  # test için şablon

	yon_cizgisi.default_color = Color(1.5, 1.3, 0.3, 1.0)
	yon_cizgisi.width = 4.0
	
	await get_tree().physics_frame
	yeni_asama()

func _process(_delta):
	if Input.is_action_just_pressed("ui_cancel"):
		toggle_pause()

	if asama_label:
		asama_label.add_theme_font_size_override("font_size", 28)
		asama_label.add_theme_color_override("font_color", Color.WHITE)
		asama_label.position = Vector2(30, 80)

	# raycastlerin duvarı görebilmesi için bekleme 
	# (topun çarpacağı tam noktayı ve açıyı hesaplama ve
	# çarpma yerindeki yüzeyin nasıl olduğunu bulup oradan nasıl sekeceğini bulmayı sağlama)
	



func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not top_firlatildi and not seviye_geciriliyor:
			ates_et()


func _draw() -> void:
	if not yakalama_alanini_goster:
		return
	for i in range(delikler.size()):
		if not delik_alindi[i]:
			draw_circle(delik_merkezi(delik_gorselleri[i]), delik_yakalama_mesafesi, Color(1, 0, 0, 0.3))


func delik_merkezi(gorsel: Sprite2D) -> Vector2:
	# deliğin merkezini hesaplama
	var yerel_merkez: Vector2 = gorsel.offset
	if not gorsel.centered and gorsel.texture:
		yerel_merkez += gorsel.texture.get_size() / 2.0
	return gorsel.global_transform * yerel_merkez


func _physics_process(delta: float) -> void:
	if yakalama_alanini_goster:
		queue_redraw()

	if seviye_geciriliyor:
		yon_cizgisi.visible = false
		return

	if not top_firlatildi:
		yon_cizgisi.visible = true
		nisan_cizgisini_ciz()
		return

	yon_cizgisi.visible = false
	topu_hareket_ettir(delta)


# topun ilerlemesi ve maks süre bitene kadar sekmesi
func topu_hareket_ettir(delta: float) -> void:
	atis_suresi_kalan -= delta
	var kalan: float = HIZ * delta

	var space_state: PhysicsDirectSpaceState2D = top.get_world_2d().direct_space_state
	var haric: Array[RID] = [top.get_rid()]

	for adim in range(MAKS_ADIM_PER_KARE):
		if kalan <= 0.001:
			break

		var onceki: Vector2 = top.global_position
		var hedef_nokta: Vector2 = onceki + top_yon * (kalan + TOP_YARICAPI)

		var query := PhysicsRayQueryParameters2D.create(onceki, hedef_nokta)
		query.exclude = haric
		var sonuc: Dictionary = space_state.intersect_ray(query)

		var yeni: Vector2 = onceki
		var sekti: bool = false
		var normal: Vector2 = Vector2.ZERO

		if sonuc:
			var vurus: Vector2 = sonuc.position + sonuc.normal * TOP_YARICAPI
			var mesafe: float = onceki.distance_to(vurus)
			if mesafe <= kalan:
				yeni = vurus
				kalan -= maxf(mesafe, 1.0)  # her seferinde az da olsa hareket
				normal = sonuc.normal
				sekti = true

		if not sekti:
			yeni = onceki + top_yon * kalan
			kalan = 0.0

		top.global_position = yeni

		if delikleri_kontrol_et(onceki, yeni):
			return

		if sekti:
			top_yon = top_yon.bounce(normal)
			# duvara çarpma efekti
			if hit_sesi and hit_sesi.stream:
				hit_sesi.play()

	if atis_suresi_kalan <= 0.0:
		topu_sifirla()


# hareket edilen çizgideki delikleri kontrol
# deliklerin hepsinden geçtiyse aşama ilerlesin
func delikleri_kontrol_et(onceki: Vector2, yeni: Vector2) -> bool:
	for i in range(delikler.size()):
		if delik_alindi[i]:
			continue

		var merkez: Vector2 = delik_merkezi(delik_gorselleri[i])
		var en_yakin: Vector2 = Geometry2D.get_closest_point_to_segment(merkez, onceki, yeni)

		if en_yakin.distance_to(merkez) < delik_yakalama_mesafesi:
			delik_alindi[i] = true

			if tum_delikler_alindi():
				# son deliğin animasyonu gelir
				top.global_position = merkez
				# aşama bitişi ses
				if laser_sesi and laser_sesi.stream:
					laser_sesi.play()
				asama_gec()
				return true

			delikler[i].visible = false
	return false


func tum_delikler_alindi() -> bool:
	for alindi in delik_alindi:
		if not alindi:
			return false
	return true


func asama_gec() -> void:
	seviye_geciriliyor = true
	top_firlatildi = false
	mevcut_asama += 1

	await top_kaybolma_animasyonu()
	await get_tree().create_timer(ASAMA_GECIS_SURESI).timeout
	yeni_asama()


# topun küçülüp dönüp sönüp deliğin içine girmesi
func top_kaybolma_animasyonu() -> void:
	var tween: Tween = create_tween().set_parallel(true)
	tween.tween_property(top_gorsel, "scale", Vector2.ZERO, KAYBOLMA_SURESI) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(top_gorsel, "rotation", top_gorsel_rotasyon + PI, KAYBOLMA_SURESI) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(top_gorsel, "modulate:a", 0.0, KAYBOLMA_SURESI)
	await tween.finished


# yeni aşamada topun yeni görseli gelir
func top_gorselini_sifirla() -> void:
	top_gorsel.scale = top_gorsel_olcek
	top_gorsel.rotation = top_gorsel_rotasyon
	top_gorsel.modulate.a = 1.0


# nişan çizgisi (yolu hesaplama) ve aşama üretimi
func yol_hesapla(baslangic: Vector2, yon: Vector2) -> Array[Vector2]:
	var noktalar: Array[Vector2] = []
	var mevcut_konum: Vector2 = baslangic
	var mevcut_yon: Vector2 = yon.normalized()
	noktalar.append(baslangic)

	var space_state: PhysicsDirectSpaceState2D = top.get_world_2d().direct_space_state
	var haric: Array[RID] = [top.get_rid()]

	# Son tur (i == MAKS_SEKME_SAYISI) sadece kısa bir ek parça içindir
	for i in range(MAKS_SEKME_SAYISI + 1):
		var son_parca: bool = (i == MAKS_SEKME_SAYISI)
		var uzunluk: float = EK_MESAFE if son_parca else RAY_UZUNLUGU
		var hedef_nokta: Vector2 = mevcut_konum + mevcut_yon * uzunluk

		var query := PhysicsRayQueryParameters2D.create(mevcut_konum, hedef_nokta)
		query.exclude = haric

		var sonuc: Dictionary = space_state.intersect_ray(query)
		if sonuc:
			var vurus: Vector2 = sonuc.position + sonuc.normal * TOP_YARICAPI
			noktalar.append(vurus)
			if son_parca:
				break
			mevcut_yon = mevcut_yon.bounce(sonuc.normal)
			mevcut_konum = vurus
		else:
			noktalar.append(hedef_nokta)
			break

	return noktalar


# topun fareye izleyeceği ilk yol (cizgi üretimi için)
func nisan_yolu() -> Array[Vector2]:
	var baslangic: Vector2 = top.global_position
	var fare_pozisyonu: Vector2 = get_global_mouse_position()

	if baslangic.distance_to(fare_pozisyonu) < MIN_NISAN_MESAFESI:
		var bos: Array[Vector2] = []
		return bos

	return yol_hesapla(baslangic, fare_pozisyonu - baslangic)


func nisan_cizgisini_ciz() -> void:
	yon_cizgisi.clear_points()
	yon_cizgisi.global_position = Vector2.ZERO
	for nokta in nisan_yolu():
		yon_cizgisi.add_point(nokta)


func ates_et() -> void:
	var baslangic: Vector2 = top.global_position
	var fare_pozisyonu: Vector2 = get_global_mouse_position()

	if baslangic.distance_to(fare_pozisyonu) < MIN_NISAN_MESAFESI:
		return

	top_yon = (fare_pozisyonu - baslangic).normalized()
	atis_suresi_kalan = maks_atis_suresi
	top_firlatildi = true


func topu_sifirla() -> void:
	# süre dolunca aşamanın tekrar edilmesi
	top_firlatildi = false
	top.global_position = top_baslangic_konumu
	for i in range(delikler.size()):
		delik_alindi[i] = false
		delikler[i].visible = true


func yeni_asama() -> void:
	top_firlatildi = false
	seviye_geciriliyor = false

	delikleri_temizle()
	top_gorselini_sifirla()

	top_baslangic_konumu = rastgele_konum()
	top.global_position = top_baslangic_konumu
	top.rotation = 0.0

	for konum in cozulebilir_konumlar_bul(delik_sayisi_hesapla()):
		delik_olustur(konum)

	if asama_label:
		asama_label.text = "Aşama: " + str(mevcut_asama)


# mevcut aşamadaki delik sayısı hesaplanır
func delik_sayisi_hesapla() -> int:
	for kademe in DELIK_KADEMELERI:
		if mevcut_asama >= kademe[0]:
			return kademe[1]
	return 1


# Her aşamanın çözümü olması için,
# rastgele bir atış simüle edip delikleri o yolun üzerine yerleştirme
func cozulebilir_konumlar_bul(sayi: int) -> Array[Vector2]:
	for deneme in range(MAKS_URETIM_DENEMESI):
		var atis_yolu: Array[Vector2] = yol_hesapla(
			top_baslangic_konumu, Vector2.from_angle(randf() * TAU)
		)
		if atis_yolu.size() < 2:
			continue

		var toplam: float = yol_uzunlugu(atis_yolu)
		var secilen: Array[Vector2] = []

		for j in range(ADAY_DENEMESI):
			if secilen.size() >= sayi:
				break
			var aday: Vector2 = yolda_nokta(atis_yolu, randf_range(0.0, toplam))
			if konum_uygun_mu(aday, secilen):
				secilen.append(aday)

		if secilen.size() == sayi:
			return secilen

	# Çözülebilir seviye oluşturulamazsa rastgele yerleşim oluşturulması
	push_warning("Çözülebilir seviye bulunamadı, rastgele yerleşim kullanıldı.")
	var yedek: Array[Vector2] = []
	for j in range(ADAY_DENEMESI * sayi):
		if yedek.size() >= sayi:
			break
		var aday: Vector2 = rastgele_konum()
		if konum_uygun_mu(aday, yedek):
			yedek.append(aday)
	return yedek


func konum_uygun_mu(aday: Vector2, secilenler: Array[Vector2]) -> bool:
	var alan := Rect2(MIN_X, MIN_Y, MAX_X - MIN_X, MAX_Y - MIN_Y)
	if not alan.has_point(aday):
		return false
	if aday.distance_to(top_baslangic_konumu) < MIN_TOP_DELIK_MESAFESI:
		return false
	for diger in secilenler:
		if aday.distance_to(diger) < MIN_DELIK_ARASI:
			return false
	return true


func yol_uzunlugu(noktalar: Array[Vector2]) -> float:
	var toplam: float = 0.0
	for i in range(1, noktalar.size()):
		toplam += noktalar[i - 1].distance_to(noktalar[i])
	return toplam


# yolun başından verilen mesafedeki noktayı döndürme
func yolda_nokta(noktalar: Array[Vector2], mesafe: float) -> Vector2:
	var kalan: float = mesafe
	for i in range(1, noktalar.size()):
		var parca: float = noktalar[i - 1].distance_to(noktalar[i])
		if kalan <= parca:
			return noktalar[i - 1].move_toward(noktalar[i], kalan)
		kalan -= parca
	return noktalar[noktalar.size() - 1]


func delik_olustur(konum: Vector2) -> void:
	var kopya: Node2D = delik_sablon.duplicate()
	kopya.visible = true
	add_child(kopya)

	var gorsel: Sprite2D = kopya.get_node("Sprite2D")
	kopya.global_position = konum
	kopya.force_update_transform()

	# Sprite, Area2D'ye göre ofsetliyse görsel merkezi hedef konuma getir
	kopya.global_position += konum - delik_merkezi(gorsel)
	kopya.force_update_transform()

	delikler.append(kopya)
	delik_gorselleri.append(gorsel)
	delik_alindi.append(false)


func delikleri_temizle() -> void:
	for d in delikler:
		d.queue_free()
	delikler.clear()
	delik_gorselleri.clear()
	delik_alindi.clear()


func rastgele_konum() -> Vector2:
	return Vector2(randf_range(MIN_X, MAX_X), randf_range(MIN_Y, MAX_Y))


func toggle_pause():
	get_tree().paused = !get_tree().paused
	pause_menu.visible = get_tree().paused
