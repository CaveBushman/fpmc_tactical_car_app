import 'package:flutter/material.dart';

import '../models/search_text.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';

/// One how-to in the in-app help.
class HelpTopic {
  const HelpTopic(this.section, this.title, this.body);

  final String section;
  final String title;
  final String body;

  bool matches(String query) {
    final folded = foldForSearch(query);
    return folded.isEmpty ||
        foldForSearch('$section $title $body').contains(folded);
  }
}

/// Short Czech how-tos for the field, grouped by situation.
const helpTopics = [
  // Mapa
  HelpTopic(
    'Mapa',
    'Moje poloha a souřadnice',
    'Panel vlevo nahoře ukazuje vaši polohu v MGRS a přesnost GPS. '
        'Klepnutím ho rozbalíte nebo sbalíte. Tlačítko s terčíkem vrátí mapu '
        'na vaši pozici a mapa ji pak sleduje; posunutím mapy prstem '
        'sledování vypnete.',
  ),
  HelpTopic(
    'Mapa',
    'Směr jízdy nahoře',
    'Kompasové tlačítko vpravo nahoře přepíná „sever nahoře“ a „směr '
        'jízdy nahoře“. Mapa se otáčí podle kurzu z GPS od rychlosti '
        '1,5 m/s; ručička v tlačítku ukazuje sever.',
  ),
  HelpTopic(
    'Mapa',
    'Informace o místě',
    'Klepněte do mapy: ukáže se MGRS, souřadnice, azimut a vzdálenost od '
        'vás. Odsud místo uložíte jako bod, pošlete skupině nebo k němu '
        'spustíte navigaci.',
  ),
  HelpTopic(
    'Mapa',
    'Nový bod',
    'Dlouhý stisk na mapě otevře nový bod: typ (RALLY, MEDEVAC, DANGER, '
        'OBS, SUPPLY), kód, poznámku a zda ho hned poslat skupině. Body '
        'upravíte tužkou a smažete košem v seznamu bodů ve spodním panelu.',
  ),
  HelpTopic(
    'Mapa',
    'Zadání souřadnic',
    'Tlačítko se špendlíkem vlevo dole: zadejte celé MGRS '
        '(33U VR 58335 40478), bez zóny (VR 58335 40478), jen čísla '
        '(58335 40478 – zóna a čtverec se doplní podle vás) nebo stupně '
        '(50.01, 14.45). Mapa na místo skočí a otevře informace o něm.',
  ),
  HelpTopic(
    'Mapa',
    'Měření vzdálenosti',
    'Pravítko vlevo dole zapne měření: klepáním přidáváte body, panel '
        'ukazuje poslední úsek (vzdálenost, azimut) a celkovou délku. '
        '„Od mé pozice“ začne u vás, „Zpět“ vrátí poslední bod.',
  ),
  HelpTopic(
    'Mapa',
    'Stopy a stáří bodů',
    'Modré tečkované čáry jsou trasy členů týmu za posledních 30 minut. '
        'Body starší než hodina jsou na mapě zesvětlené; v seznamu bodů je '
        'u přijatých bodů jejich stáří a tlačítko pro smazání přijatých '
        'bodů starších než 6 hodin.',
  ),
  HelpTopic(
    'Mapa',
    'Offline mapy',
    'Systém → Mapy: stáhněte oblast pro práci bez internetu. Funguje jen '
        'se zdrojem dlaždic, který hromadné stahování povoluje.',
  ),
  // Navigace
  HelpTopic(
    'Navigace',
    'Navigace k cíli',
    'Šipkou na kartě cíle ve spodním panelu nebo „Navigovat sem“ u místa '
        'na mapě zvolíte cíl. K cíli vede oranžová čára, dole je azimut, '
        'vzdálenost a čas příjezdu podle vaší rychlosti. Navigace skončí '
        '50 m od cíle nebo křížkem.',
  ),
  HelpTopic(
    'Navigace',
    'Sraz',
    'U bodu v seznamu bodů zvolte „Sraz zde“ a čas. Skupina dostane zprávu '
        'a všichni vidí pruh se zbývajícím časem a délkou cesty podle své '
        'rychlosti; zčervená, když to nestihnete. Kdo sraz vyhlásil, ho '
        'křížkem zruší všem; ostatní si ho jen skryjí. Pruh zmizí půl '
        'hodiny po čase srazu.',
  ),
  HelpTopic(
    'Navigace',
    'Základna',
    'V úpravě bodu zapněte „Moje základna“. Základna má na mapě domeček a '
        'v režimu auta je v seznamu cílů vždy první. Je uložená jen ve '
        'vašem zařízení.',
  ),
  // Zprávy
  HelpTopic(
    'Zprávy a hlášení',
    'Skupiny a soukromé zprávy',
    'Nahoře na záložce Zprávy vyberete skupinu (každá má svůj kanál '
        'T-Beamu). Přepínačem Skupina/Osoba pošlete zprávu jen jednomu '
        'členovi. Červené číslo u záložky a u skupiny jsou nepřečtené zprávy.',
  ),
  HelpTopic(
    'Zprávy a hlášení',
    'Rychlé zprávy a hlášení',
    'Řádek rychlých zpráv pošle šablonu jedním klepnutím; šablony upravíte '
        'v Nastavení. Tlačítka CONTACT, MEDEVAC a SITREP otevřou formulář '
        'hlášení; CONTACT se ostatním zakreslí jako bod DANGER.',
  ),
  HelpTopic(
    'Zprávy a hlášení',
    'Doručení a hledání',
    'U odeslané zprávy je vidět, zda ji T-Beam doručil; nedoručenou lze '
        'poslat znovu. Pole nad seznamem hledá v textu i odesílateli bez '
        'ohledu na diakritiku, „Prioritní“ ukáže jen prioritní zprávy.',
  ),
  HelpTopic(
    'Zprávy a hlášení',
    'Akce u zprávy',
    'Dlouhý stisk na zprávě: „Ukázat na mapě“, pokud zpráva obsahuje '
        'souřadnice (MGRS nebo LAT/LON), soukromá odpověď odesílateli, '
        'navigace k němu a kopírování textu.',
  ),
  HelpTopic(
    'Zprávy a hlášení',
    'Bez T-Beamu přes internet',
    'Když není T-Beam připojený, zprávy skupiny a poloha jdou přes '
        'internet (ikona mráčku). Soukromé zprávy a jiné skupiny potřebují '
        'T-Beam.',
  ),
  // Tým
  HelpTopic(
    'Tým a stavy',
    'Seznam týmu',
    'Záložka Tým: nahoře vy, pak OK, STALE (5–15 min bez zprávy) a LOST '
        '(déle), uvnitř podle vzdálenosti. Členové, kteří se neozvali '
        '24 hodin, se skryjí.',
  ),
  HelpTopic(
    'Tým a stavy',
    'Akce u člena',
    'Na kartě člena v Týmu: „Navigovat“ spustí navigaci k němu (cíl se '
        'posouvá s ním), „Zpráva“ otevře soukromou zprávu jen pro něj.',
  ),
  HelpTopic(
    'Tým a stavy',
    'Můj stav',
    'Nahoře na záložce Tým (nebo tlačítkem v režimu auta) zvolíte stav: '
        'OK, V POHYBU, NA POZICI, ZRANĚN, POTŘEBUJI PODPORU, MIMO AKCI. '
        'Pošle se skupině a ostatní ho uvidí u vás v týmu i na mapě.',
  ),
  // SOS
  HelpTopic(
    'SOS a výstrahy',
    'SOS',
    'Tlačítko SOS (Zprávy nebo režim auta) po potvrzení posílá každou '
        'minutu výzvu s vaší polohou, dokud ji nezrušíte – i když se mezitím '
        'telefon nebo aplikace restartuje (po přihlášení se SOS samo obnoví). '
        'Výzvu od člena týmu ukáže červený pruh s vibrací; „Beru“ mu odpoví.',
  ),
  HelpTopic(
    'SOS a výstrahy',
    'Výstrahy',
    'Červený pruh a vibrace upozorní: do 300 m od bodu DANGER, když člen '
        'hlásí ZRANĚN nebo POTŘEBUJI PODPORU a když se člen 15 minut '
        'neozve. Při baterii T-Beamu na 20 % a méně se ukáže hlášení. '
        'Varování u nebezpečí a ztrátu spojení lze vypnout v Nastavení.',
  ),
  // Auto
  HelpTopic(
    'Režim auta',
    'Režim auta',
    'Ikona auta v horní liště. Velké tlačítko PTT (držet), ZPRÁVA, NA '
        'POZICI a SOS, váš stav, cíl s časem příjezdu (klepnutím vyberete '
        'jiný) a noční režim. Displej při něm nezhasne.',
  ),
  HelpTopic(
    'Režim auta',
    'Vysílačka (PTT)',
    'Tlačítko PTT držte po dobu hovoru. V Nastavení lze jako PTT použít '
        'tlačítko hlasitosti dolů; hlasový kanál funguje i s aplikací na '
        'pozadí.',
  ),
  // Nastavení
  HelpTopic(
    'Nastavení a zařízení',
    'Připojení T-Beamu',
    'Systém → Meshtastic → Vyhledat T-Beam. Aplikace načte kanály a '
        'upozorní, pokud skupina používá kanál, který T-Beam nemá. Poloha '
        'telefonu se posílá do sítě, pokud to nevypnete.',
  ),
  HelpTopic(
    'Nastavení a zařízení',
    'Displej a baterie',
    'Velikost písma, noční režim (i automaticky podle soumraku), mřížka '
        'MGRS, celá obrazovka a úsporný režim (řidší GPS a hlášení polohy) '
        'najdete v Systém → Nastavení.',
  ),
  HelpTopic(
    'Nastavení a zařízení',
    'Mise a deník',
    'Systém → Mise: stopa, deník událostí (SOS, stavy, výstrahy, body) a '
        'export mise do GPX a CSV. Po restartu telefonu nebo aplikace se '
        'po přihlášení obnoví i zprávy, body, navigace, sraz a stavy týmu.',
  ),
  // Bezpečnost
  HelpTopic(
    'Bezpečnost',
    'Poloha pro velitele',
    'Přihlášená aplikace posílá na server vaši polohu, stav a baterii '
        'T-Beamu – nejvýš každé 2 minuty (v úsporném režimu 5), při změně '
        'stavu hned. Velitelé ji vidí v panelu na stránce Situace. Server '
        'drží jen poslední polohu, historii pohybu neukládá.',
  ),
  HelpTopic(
    'Bezpečnost',
    'Odhlášení a nouzový výmaz',
    'Data v zařízení jsou šifrovaná. Odhlášení smaže zprávy, body a polohy. '
        'Nouzový výmaz v nabídce uživatele (vpravo nahoře) po podržení 3 s '
        'smaže vše včetně nastavení a offline map.',
  ),
];

/// Searchable in-app help.
class HelpPage extends StatefulWidget {
  const HelpPage({super.key});

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  final TextEditingController _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text;
    final topics = helpTopics.where((topic) => topic.matches(query)).toList();
    final searching = query.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('Nápověda')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          TacticalSearchField(
            key: const ValueKey('help-search'),
            controller: _search,
            label: 'Hledat v nápovědě',
            hint: 'např. základna, sos, souřadnice',
          ),
          const SizedBox(height: 8),
          if (topics.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Nic nenalezeno.',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              ),
            ),
          for (final (index, topic) in topics.indexed) ...[
            if (index == 0 || topics[index - 1].section != topic.section)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
                child: Text(
                  topic.section.toUpperCase(),
                  style: const TextStyle(
                    color: sand,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            Card(
              child: ExpansionTile(
                key: ValueKey('help-${topic.title}'),
                initiallyExpanded: searching,
                title: Text(
                  topic.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                expandedAlignment: Alignment.centerLeft,
                children: [Text(topic.body)],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
