# Mindrop klasörleri ve widget’ları

Bu dosya, Mindrop’ta kayıtları düzenleme, türlerine göre kullanışlı detaylar gösterme ve seçili bilgileri iPhone ekranında görünür tutma konusunda konuştuğumuz ürün kararlarını toplar.

## Hızlı kayıt

Anahtar kelimeyi ve değeri girip kaydetmek temel akıştır. Kullanıcı klasör seçmeden kaydederse kayıt varsayılan klasöre eklenir. Klasörü, saklama süresini ve widget görünürlüğünü kayıt sırasında ya da sonradan belirleyebilir. Örneğin havaalanında `gate` ve `21` yazıp hemen kaydedebilir. Kayıt daha sonra Spotlight’ta aynı anahtar kelimeyle bulunur.

## Otomatik kategoriler ve klasörler

- **Kategori**, kaydın türünü belirtir. Wi‑Fi, Bağlantılar ve Kodlar gibi mevcut kategoriler otomatik belirlenir.
- **Klasör**, kullanıcının kendi bağlamını belirtir. Her kayıt tek bir klasöre aittir. Mindrop başlangıçta Genel klasörünü sağlar. Kullanıcı İş, Aile veya Roma Seyahati gibi klasörler oluşturup kayıtlarını bunlara taşıyabilir.
- Ana ekran ilk açılıştan itibaren klasör listesidir. Başlangıçta Genel görünür. Kullanıcının oluşturduğu klasörler aynı listeye eklenir. Silinmiş kayıtlar varsa listenin sonunda Son Silinenler görünür.
- Bir klasöre dokunulduğunda kayıtları kategori başlıkları altında iPhone ve iPad’in mevcut kart grid’iyle göster. Geri gidildiğinde klasör listesine dön. Örneğin İş klasöründe Wi‑Fi ve Bağlantılar ayrı bölümler olabilir.
- Klasör üyeliği olmayan mevcut kayıtları okuma sırasında varsayılan klasöre ait kabul et. Mevcut kayıt kimliklerini koru. İlk sürümde klasörler ve üyelikleri cihazda saklanır.

### Klasörleri koleksiyon olarak kullanmak

- **Favori Restoranlarım.** Kullanıcı Google Maps veya Apple Maps’ten bir restoranın paylaşım bağlantısını kaydeder. İster kayıt sırasında ister sonra bu klasöre ekler. Klasörde mekân adlarını listeler, bir kaydı açtığında sakladığı bağlantıyla haritaya gider.
- **İzlemek İstediğim Filmler.** Kullanıcı duyduğu film adını hızlıca kaydeder ve bu klasörde biriktirir. Film adı, uygun olduğunda yıl bilgisiyle birlikte listelenir. Afiş gibi görseller detayda yer alır.

### Film ve harita detayları

- **Film kategorisi.** Film kaydı adıyla kaydedilebilir. Detayda güvenilir eşleşme varsa film adını, yılı ve kullanım izni olan afişi göster. Birden fazla film aynı adı taşıyorsa kullanıcı detaydan doğru filmi seçebilir. Eşleşme veya afiş yoksa yazılan adla kayıt kullanılabilir. Film verisi ve afiş yüklemesi kayıttan sonra yapılır. Afiş sağlayıcısı açık karar. TMDB’nin ücretsiz kullanımı atıf şartıyla ticari olmayan kullanımlar içindir. Görsel kaynağı seçilirken Mindrop’un kullanımına uygun lisans doğrulanır. [TMDB API kullanım koşulları](https://developer.themoviedb.org/docs/faq)
- **Harita bağlantısı.** Google Maps veya Apple Maps paylaşım bağlantısının işaret ettiği yer güvenilir biçimde belirlenebiliyorsa detayda mekân adını, varsa adresini ve işaretli küçük bir harita önizlemesini göster. Asıl bağlantıyı sakla ve **Google Maps’te aç** veya **Apple Haritalar’da aç** eylemi sun. Konumu çözülemeyen bağlantılarda da aynı açma eylemi kullanılabilir. Küçük harita için konum elde edilebilen kayıtlarda iOS’taki MapKit önizlemesini değerlendir. [MapKit harita görüntüleri](https://developer.apple.com/documentation/mapkit/mkmapsnapshotter) · [Apple Maps bağlantıları](https://developer.apple.com/documentation/mapkit/unified-map-urls) · [Google Maps bağlantıları](https://developers.google.com/maps/documentation/urls/get-started)

## Geçici kayıtlar

**Geçici**, saklama süresi olan kayıtların otomatik göründüğü bir listedir. Kullanıcı mevcut saklama süresi seçeneğinden **7 gün** gibi bir süre belirleyebilir. Liste, her kayıt için *“2 gün kaldı”* gibi kısa bir bilgi gösterebilir.

Örneğin `gate` kaydı aynı anda Roma Seyahati klasöründe ve Geçici listesinde görünür. Süresi dolduğunda Çöp Kutusu’na taşınır ve Spotlight sonuçlarından çıkarılır. Widget’ta gösterilecek bir sonraki kaydı seçerken de süresi dolmuş kayıt atlanır.

## Yığın ve widget’lar

**Yığın**, kullanıcının bir süre gözünün önünde tutmak istediği kayıtların sıralı listesidir. İlk sürüm için tek bir Yığın öneriyoruz. Örneğin `parking` kaydı Seyahat klasöründe dururken Yığın’a da eklenebilir. Her iki yer aynı kayda açılır.

- **Widget’ta göster** seçeneği, kayıt oluştururken veya sonradan detay ekranından açılabilir. Seçilen kayıt Yığın’da görünür.
- Kullanıcı, hangi kaydın öncelikli olduğunu Yığın’daki sıralamayı değiştirerek belirler. İlk widget’lar en üstteki, süresi dolmamış ve gösterilebilen kaydı kullanır.
- Widget’ın ekrana yerleştirilmesi iOS üzerinden yapılır. Kullanıcı widget’ı ekledikten sonra içeriği Mindrop’tan yönetir. Yenilemenin zamanlamasını iOS belirler. [Widget ekleme](https://support.apple.com/en-us/118610) · [Widget yenileme](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date/)
- Hassas kayıtların değerlerine ve QR kodlarına Mindrop’taki kilit açma akışı üzerinden erişilir. Widget yalnızca hassas olmayan değerleri gösterir.

### İlk sürüm önerisi

| Widget | Gösterilen bilgi |
| --- | --- |
| Kilit ekranında saatin altında dikdörtgen | Bir kayıt. Küçük anahtar kelime ve belirgin değer. Örneğin `Kalkış kapısı` ve `21`. |
| Ana ekranda küçük | Bir kayıt. Anahtar kelime ve değer. Örneğin `Otopark` ve `B2 · Mavi · 147`. |

### Sonraki seçenekler

- Ana ekranda orta boy widget ile Yığın’dan iki veya üç kayıt göstermek.
- Widget ayarlarında Yığın’ın ilk kaydı ile kullanıcının sabitlediği belirli bir kayıt arasında seçim sunmak.
- Kilit ekranında saatin üstünde kısa tek satır, saatin altında yuvarlak alanda ise `21` gibi birkaç karakter göstermek.
- Kilit ekranının altına veya Denetim Merkezi’ne doğrudan kayıt ekranını açan bir **Yeni kayıt** kontrolü eklemek.

[Apple’ın widget tasarım rehberi](https://developer.apple.com/design/human-interface-guidelines/widgets) · [Yapılandırılabilir widget’lar](https://developer.apple.com/documentation/widgetkit/making-a-configurable-widget) · [Kilit ekranı ve Denetim Merkezi kontrolleri](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system)
