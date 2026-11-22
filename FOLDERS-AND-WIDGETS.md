# Mindrop klasörleri ve widget’ları

Bu dosya, Mindrop’ta kayıtları düzenleme, türlerine göre kullanışlı detaylar gösterme ve seçili bilgileri iPhone ekranında görünür tutma konusunda konuştuğumuz ürün kararlarını toplar.

## Hızlı kayıt

Anahtar kelimeyi ve değeri girip kaydetmek temel akıştır. Kullanıcı klasör seçmeden kaydederse kayıt varsayılan klasöre eklenir. Klasörü, saklama süresini ve Yığın üyeliğini kayıt sırasında ya da sonradan belirleyebilir. Örneğin havaalanında `gate` ve `21` yazıp hemen kaydedebilir. Kayıt daha sonra Spotlight’ta aynı anahtar kelimeyle bulunur.

## Otomatik kategoriler ve klasörler

- **Kategori**, kaydın türünü belirtir. Wi‑Fi, Bağlantılar ve Kodlar gibi mevcut kategoriler otomatik belirlenir.
- **Klasör**, kullanıcının kendi bağlamını belirtir. Her kayıt tek bir klasöre aittir. Mindrop başlangıçta Genel klasörünü sağlar. Kullanıcı İş, Aile veya Roma Seyahati gibi klasörler oluşturup kayıtlarını bunlara taşıyabilir.
- Ana ekran ilk açılıştan itibaren klasör listesidir. Başlangıçta Genel görünür. Kullanıcının oluşturduğu klasörler aynı listeye eklenir. Silinmiş kayıtlar varsa listenin sonunda Son Silinenler görünür.
- Bir klasöre dokunulduğunda kayıtları kategori başlıkları altında iPhone ve iPad’in mevcut kart grid’iyle göster. Geri gidildiğinde klasör listesine dön. Örneğin İş klasöründe Wi‑Fi ve Bağlantılar ayrı bölümler olabilir.
- Klasörde Kayıt Seç ile birden fazla kaydı işaretle. Arama sonuçlarından ve filtrelenmiş kategorilerden seçime kayıt ekle. Arama veya kategori filtresi değiştiğinde ya da kaldırıldığında seçimi koru. Seçim menüsünden kayıtları başka bir klasöre taşı, Yığın’a ekle veya onaydan sonra Son Silinenler’e gönder. Seçimin bir bölümü Yığın’a eklenebiliyorsa eklenecek yeni kayıt sayısını menüde göster.
- Özel klasör, bağlam menüsündeki Klasörü Sil eylemi onaylandıktan sonra kaldırılır. İçindeki kayıtlar Son Silinenler’e gider ve buradan geri yüklenen kayıtlar Genel’e döner. Genel, varsayılan klasör olarak korunur.
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

**Yığın**, kullanıcının bir süre gözünün önünde tutmak istediği kayıtların sıralı listesidir. iPhone ve iPad’de Genel’in hemen üstündeki önizlemeden, Mac’te kenar çubuğundan açılır. Örneğin `parking` kaydı Seyahat klasöründen ve Yığın’dan açılabilir. Üyelik ve sıra bu aşamada cihazda saklanır.

- **Yığında Göster** seçeneği yeni kayıt formunda ve kayıt detayında yer alır. Yeni seçimler listenin sonuna eklenir.
- Yığın’a uygun bir kaydın bağlam menüsünde **Yığına Ekle** eylemi **Kopyala**’nın hemen altında yer alır.
- **Kayıt Seç** eylemi, tüm klasörlerdeki uygun kayıtları klasör başlıklarına göre listeler. Kullanıcı arayabilir ve birden fazla kaydı ekleyebilir.
- Yığın’da anahtar kelime küçük, değer belirgin görünür. Kullanıcı sıra değiştirerek önceliği belirler. iPhone ve iPad’de bir satırı sola kaydırınca **Yığından Çıkar** görünür. Tam kaydırma üyeliği hemen kaldırır ve kayıt kendi klasöründe kalır.
- Yığın’da hassas olmayan, süresi dolmamış ve aktif kayıtlar görünür. Bir kayıt yeniden uygun hale gelirse Yığın’daki konumundan açılabilir.

### Widget davranışı

- Widget, düzenin kapasitesine göre Yığın’ın başından uygun kayıtları alır.
- Widget’ın ekrana yerleştirilmesi iOS üzerinden yapılır. Kullanıcı widget’ı ekledikten sonra içeriği Mindrop’tan yönetir. Yenilemenin zamanlamasını iOS belirler. [Widget ekleme](https://support.apple.com/en-us/118610) · [Widget yenileme](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date/)
- Hassas kayıtların değerlerine ve QR kodlarına Mindrop’taki kilit açma akışı üzerinden erişilir. Widget yalnızca hassas olmayan değerleri gösterir.

### Ana Ekran widget’ı ve uygulama önizlemesi

Orta boy widget, Yığın’daki ilk altı uygun kaydı iki sütunlu, üç satırlı ızgarada gösterir. Kullanılmayan hücreler boş görünür ve ızgara çizgileri tüm satır ve sütunlar boyunca devam eder. Dolu hücrelerde küçük anahtar kelimenin altında daha büyük değer bulunur. `C24` ve `18A` gibi kısa değerler tek satırda görünür. Otopark konumu gibi uzun değerler iki satıra yayılabilir.

Mindrop ana ekranında **Yığın** başlığı ve şevron, Genel’in hemen üstündeki ızgaranın üzerinde yer alır. Önizleme Yığın ekranını açar. Yığın boşken **Kayıt Seç** düğmesi doğrudan kayıt seçiciyi açar. Önizleme ve Ana Ekran widget’ı aynı kayıt sırasını ve ızgara yerleşimini kullanacak şekilde tasarlanır.

### Kilit ekranı düzenleri

İlk odak, iPhone’da saatin altındaki dikdörtgen widget (`accessoryRectangular`). Beş düzenin tamamı Mindrop’ta sunulabilecek seçenekler olarak değerlendiriliyor. İlk deneme için Alt alta önerildi. Varsayılan düzen ve düzen seçiminin nereden yapılacağı açık.

| Düzen | Kapasite | Yerleşim |
| --- | --- | --- |
| Tek odak | 1 kayıt | Küçük anahtar kelime üstte, en büyük değer altta. Örnek kayıt `Kalkış kapısı` ve `C24`. |
| Alt alta | 2 kayıt | İki kayıt dikey dizilir. Her değer tam genişliği kullanır. `C24` ile `B2 · Mavi · 147` gibi farklı uzunluktaki değerler aynı anda okunabilir. |
| Yan yana | 2 kayıt | Eşit iki sütunda anahtar kelimeler değerlerin üstünde yer alır. `C24` ve `18A` gibi kısa değerler için daha büyük yazı kullanılabilir. |
| Öncelikli | 3 kayıt | Yığın’ın ilk kaydı üstte tam genişlikte ve daha büyük gösterilir. İki kısa kayıt altta yan yana yer alır. |
| Dörtlü ızgara | En fazla 4 kısa kayıt | İki sütun ve iki satırda kapı, koltuk, oda ve dolap gibi kısa kayıtlar gösterilir. Uzun bir değere tam genişlik verip üç kayda düşen düzen de denenebilir. |

Her düzende anahtar kelime ve değer birlikte okunabilmeli. Kapasiteyi kısa kodlar ve daha uzun değerlerle birlikte değerlendir. Taslaktaki `#263554` → `#101522` gradient’i duvar kâğıdını temsil eder. Widget, kilit ekranının sistem görünümüne uyum sağlar. [Apple’ın widget tasarım rehberi](https://developer.apple.com/design/human-interface-guidelines/widgets)

### Sonraki seçenekler

- Ana ekranda küçük widget ile `Otopark` ve `B2 · Mavi · 147` gibi tek bir kayıt göstermek.
- Widget ayarlarında Yığın’ın ilk kaydı ile kullanıcının sabitlediği belirli bir kayıt arasında seçim sunmak.
- Kilit ekranında saatin üstünde kısa tek satır, saatin altında yuvarlak alanda ise `21` gibi birkaç karakter göstermek.
- Kilit ekranının altına veya Denetim Merkezi’ne doğrudan kayıt ekranını açan bir **Yeni kayıt** kontrolü eklemek.

[Yapılandırılabilir widget’lar](https://developer.apple.com/documentation/widgetkit/making-a-configurable-widget) · [Kilit ekranı ve Denetim Merkezi kontrolleri](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system)
