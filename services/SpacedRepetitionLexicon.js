// SpacedRepetitionLexicon.js
// Pure lexical analyzer and CEFR level (A1-C2) extractor for English (en) and German (de).
// Combines curated Oxford 3000/5000, Cambridge EVP, Goethe-Zertifikat & DWDS core vocabulary
// with morphological stemming, German article/gender inference, and online dictionary merging.

var CEFR_LEVELS = ["A1", "A2", "B1", "B2", "C1", "C2"];

var ENGLISH_LEXICON = {
    // A1 - A2 Core
    "book": { level: "A1", pos: "noun", phonetic: "/bʊk/", meaning: "a written or printed work consisting of pages", example: "She is reading an interesting book.", synonyms: ["volume", "tome", "publication"], antonyms: [], morphology: [{"part": "bok (boks)", "kind": "root", "meaning": "beechwood tablet, written volume"}], source: "Oxford 3000 / Cambridge EVP" , meaningVi: "quyển sách, tác phẩm viết hoặc in gồm nhiều trang đóng lại"},
    "water": { level: "A1", pos: "noun", phonetic: "/ˈwɔː.tər/", meaning: "a clear liquid essential for life", example: "Please drink plenty of water every day.", synonyms: ["aqua", "liquid"], antonyms: [], morphology: [{"part": "wat- (wed-)", "kind": "root", "meaning": "wet, flowing liquid"}, {"part": "-er", "kind": "suffix", "meaning": "substance noun"}], source: "Oxford 3000 / Cambridge EVP" , meaningVi: "nước, chất lỏng trong suốt thiết yếu cho sự sống"},
    "learn": { level: "A1", pos: "verb", phonetic: "/lɜːn/", meaning: "to gain knowledge or skill by studying or experience", example: "We learn new vocabulary through spaced repetition.", synonyms: ["study", "acquire", "master"], antonyms: ["forget", "unlearn"], morphology: [{"part": "leorn (leis-)", "kind": "root", "meaning": "follow a track, acquire knowledge"}], source: "Oxford 3000 / Cambridge EVP" , meaningVi: "tiếp thu kiến thức hoặc kỹ năng qua học tập, trải nghiệm"},
    "understand": { level: "A1", pos: "verb", phonetic: "/ˌʌn.dəˈstænd/", meaning: "to know the meaning of something that someone says", example: "Do you understand how this algorithm works?", synonyms: ["comprehend", "grasp"], antonyms: ["misunderstand", "misinterpret"], morphology: [{"part": "under-", "kind": "prefix", "meaning": "among, closely between"}, {"part": "stand", "kind": "root", "meaning": "stand firm, grasp mentally"}], source: "Oxford 3000 / Cambridge EVP" , meaningVi: "hiểu, nắm được ý nghĩa hoặc bản chất của điều gì đó"},
    "available": { level: "A2", pos: "adj", phonetic: "/əˈveɪ.lə.bəl/", meaning: "able to be bought, used, or reached", example: "The offline dictionary is always available.", synonyms: ["accessible", "obtainable"], antonyms: ["unavailable", "inaccessible"], morphology: [{"part": "a- (ad-)", "kind": "prefix", "meaning": "to"}, {"part": "vail (valere)", "kind": "root", "meaning": "be strong, be of worth"}, {"part": "-able", "kind": "suffix", "meaning": "able to be"}], source: "Oxford 3000 / Cambridge EVP" , meaningVi: "có sẵn, có thể mua, sử dụng hoặc tiếp cận được"},
    "experience": { level: "A2", pos: "noun", phonetic: "/ɪkˈspɪə.ri.əns/", meaning: "knowledge or skill from doing, seeing, or feeling things", example: "Practical experience is the best teacher.", synonyms: ["practice", "know-how"], antonyms: ["inexperience"], morphology: [{"part": "ex-", "kind": "prefix", "meaning": "out of"}, {"part": "peri (periri)", "kind": "root", "meaning": "try, test, risk"}, {"part": "-ence", "kind": "suffix", "meaning": "state, result"}], source: "Oxford 3000 / Cambridge EVP" , meaningVi: "kinh nghiệm, trải nghiệm, kiến thức hoặc kỹ năng có được từ thực tế"},
    "improve": { level: "A2", pos: "verb", phonetic: "/ɪmˈpruːv/", meaning: "to get better, or to make something better", example: "Daily practice will improve your fluency.", synonyms: ["enhance", "upgrade", "refine"], antonyms: ["worsen", "deteriorate"], morphology: [{"part": "im- (en-)", "kind": "prefix", "meaning": "into"}, {"part": "prove (prode)", "kind": "root", "meaning": "profit, advantage, make better"}], source: "Oxford 3000 / Cambridge EVP" , meaningVi: "cải thiện, trở nên tốt hơn hoặc làm cho cái gì tốt hơn"},
    "schedule": { level: "A2", pos: "noun", phonetic: "/ˈʃed.juːl/", meaning: "a plan of activities or tasks and when they will happen", example: "The review schedule adapts to your memory strength.", synonyms: ["timetable", "agenda"], antonyms: [], morphology: [{"part": "sched (schida)", "kind": "root", "meaning": "strip of papyrus"}, {"part": "-ule (-ula)", "kind": "suffix", "meaning": "diminutive slip/list"}], source: "Oxford 3000 / Cambridge EVP" , meaningVi: "lịch trình, kế hoạch các hoạt động kèm thời gian thực hiện"},

    // B1 - B2 Intermediate & Upper-Intermediate
    "achieve": { level: "B1", pos: "verb", phonetic: "/əˈtʃiːv/", meaning: "to succeed in finishing something or reaching an aim", example: "Consistent review helps you achieve long-term mastery.", synonyms: ["accomplish", "attain"], antonyms: ["fail", "forfeit"], morphology: [{"part": "a- (ad-)", "kind": "prefix", "meaning": "to, toward"}, {"part": "chieve (caput)", "kind": "root", "meaning": "head, bring to completion"}], source: "Oxford 3000 / Cambridge EVP" , meaningVi: "đạt được, hoàn thành hoặc đạt tới mục tiêu sau khi nỗ lực"},
    "consequence": { level: "B1", pos: "noun", phonetic: "/ˈkɒn.sɪ.kwəns/", meaning: "a result of a particular action or situation", example: "Every design decision has a long-term consequence.", synonyms: ["outcome", "result"], antonyms: ["cause", "origin"], morphology: [{"part": "con- (com-)", "kind": "prefix", "meaning": "together, with"}, {"part": "sequ (sequi)", "kind": "root", "meaning": "follow"}, {"part": "-ence", "kind": "suffix", "meaning": "result, state"}], source: "Oxford 3000 / Cambridge EVP" , meaningVi: "hậu quả, hệ quả, kết quả của một hành động hoặc tình huống"},
    "essential": { level: "B1", pos: "adj", phonetic: "/ɪˈsen.ʃəl/", meaning: "necessary or needed; completely important", example: "Active recall is essential for durable memory.", synonyms: ["vital", "crucial"], antonyms: ["optional", "trivial"], morphology: [{"part": "ess (esse)", "kind": "root", "meaning": "to be, core essence"}, {"part": "-ent", "kind": "suffix", "meaning": "being"}, {"part": "-ial", "kind": "suffix", "meaning": "relating to"}], source: "Oxford 3000 / Cambridge EVP" , meaningVi: "thiết yếu, vô cùng quan trọng và hoàn toàn cần thiết"},
    "perspective": { level: "B2", pos: "noun", phonetic: "/pəˈspek.tɪv/", meaning: "a particular way of considering something", example: "Learning another language gives you a fresh perspective.", synonyms: ["viewpoint", "outlook"], antonyms: [], morphology: [{"part": "per-", "kind": "prefix", "meaning": "through"}, {"part": "spect (specere)", "kind": "root", "meaning": "look, see"}, {"part": "-ive", "kind": "suffix", "meaning": "relating to"}], source: "Oxford 3000 / Cambridge EVP" , meaningVi: "góc nhìn, quan điểm, cách nhìn nhận và đánh giá một vấn đề"},
    "sustainable": { level: "B2", pos: "adj", phonetic: "/səˈsteɪ.nə.bəl/", meaning: "able to continue over a period of time without causing damage", example: "A twenty-minute daily habit is much more sustainable than cramming.", synonyms: ["viable", "renewable"], antonyms: ["unsustainable", "short-lived"], morphology: [{"part": "sus- (sub-)", "kind": "prefix", "meaning": "up from below"}, {"part": "tain (tenere)", "kind": "root", "meaning": "hold, support"}, {"part": "-able", "kind": "suffix", "meaning": "able to be"}], source: "Oxford 3000 / Cambridge EVP" , meaningVi: "bền vững, có thể duy trì lâu dài mà không gây tổn hại"},
    "inevitable": { level: "B2", pos: "adj", phonetic: "/ɪˈnev.ɪ.tə.bəl/", meaning: "certain to happen and unable to be avoided or prevented", example: "Forgetting is inevitable without periodic retrieval practice.", synonyms: ["unavoidable", "certain"], antonyms: ["avoidable", "preventable"], morphology: [{"part": "in-", "kind": "prefix", "meaning": "not"}, {"part": "e- (ex-)", "kind": "prefix", "meaning": "out"}, {"part": "vit (vitare)", "kind": "root", "meaning": "shun, avoid"}, {"part": "-able", "kind": "suffix", "meaning": "able to be"}], source: "Oxford 3000 / Cambridge EVP" , meaningVi: "tất yếu, chắc chắn sẽ xảy ra và không thể tránh khỏi"},
    "comprehensive": { level: "B2", pos: "adj", phonetic: "/ˌkɒm.prɪˈhen.sɪv/", meaning: "complete and including everything that is necessary", example: "The guide provides a comprehensive overview of German grammar.", synonyms: ["thorough", "exhaustive"], antonyms: ["incomplete", "partial"], morphology: [{"part": "com-", "kind": "prefix", "meaning": "together, completely"}, {"part": "prehens (prehendere)", "kind": "root", "meaning": "grasp, seize"}, {"part": "-ive", "kind": "suffix", "meaning": "tending to"}], source: "Oxford 3000 / Cambridge EVP" , meaningVi: "toàn diện, đầy đủ và bao quát mọi khía cạnh cần thiết"},
    "ambiguous": { level: "B2", pos: "adj", phonetic: "/æmˈbɪɡ.ju.əs/", meaning: "having or expressing more than one possible meaning", example: "Avoid ambiguous prompts when designing flashcards.", synonyms: ["vague", "equivocal"], antonyms: ["clear", "unambiguous"], morphology: [{"part": "ambi-", "kind": "prefix", "meaning": "both ways, around"}, {"part": "ig (agere)", "kind": "root", "meaning": "drive, lead"}, {"part": "-uous (-ous)", "kind": "suffix", "meaning": "characterized by"}], source: "Oxford 5000 / Cambridge EVP" , meaningVi: "mơ hồ, nhập nhằng, có nhiều hơn một cách hiểu, không rõ ràng"},
    "reluctant": { level: "B2", pos: "adj", phonetic: "/rɪˈlʌk.tənt/", meaning: "not willing to do something and therefore slow to do it", example: "Learners are often reluctant to review difficult leech cards.", synonyms: ["hesitant", "unwilling"], antonyms: ["eager", "willing"], morphology: [{"part": "re-", "kind": "prefix", "meaning": "against, back"}, {"part": "luct (luctari)", "kind": "root", "meaning": "struggle, wrestle"}, {"part": "-ant", "kind": "suffix", "meaning": "being"}], source: "Oxford 5000 / Cambridge EVP" , meaningVi: "miễn cưỡng, ngần ngại, không sẵn lòng làm điều gì"},

    // C1 - C2 Advanced & Mastery
    "ubiquitous": { level: "C1", pos: "adj", phonetic: "/juːˈbɪk.wɪ.təs/", meaning: "seeming to be everywhere or in several places at the same time", example: "Smartphones have become ubiquitous in modern daily life.", synonyms: ["omnipresent", "pervasive"], antonyms: ["rare", "scarce"], morphology: [{"part": "ubique", "kind": "root", "meaning": "everywhere (where + ever)"}, {"part": "-ous", "kind": "suffix", "meaning": "full of, characterized by"}], source: "Cambridge EVP / Oxford 5000" , meaningVi: "có mặt ở khắp nơi, dường như xuất hiện ở mọi nơi cùng một lúc"},
    "ephemeral": { level: "C1", pos: "adj", phonetic: "/ɪˈfem.ər.əl/", meaning: "lasting for only a very short time; fleeting", example: "Short-term cramming creates ephemeral memories that fade within days.", synonyms: ["transient", "fleeting", "short-lived"], antonyms: ["permanent", "enduring"], morphology: [{"part": "epi-", "kind": "prefix", "meaning": "upon, for"}, {"part": "hemera", "kind": "root", "meaning": "a single day"}, {"part": "-al", "kind": "suffix", "meaning": "relating to"}], source: "Cambridge EVP" , meaningVi: "phù du, chóng tàn, chỉ tồn tại hoặc được sử dụng trong thời gian rất ngắn"},
    "resilient": { level: "C1", pos: "adj", phonetic: "/rɪˈzɪl.i.ənt/", meaning: "able to recover quickly after something unpleasant or difficult", example: "Spaced retrieval builds a resilient mental lexicon.", synonyms: ["robust", "hardy", "adaptable"], antonyms: ["fragile", "vulnerable"], morphology: [{"part": "re-", "kind": "prefix", "meaning": "back"}, {"part": "sili (salire)", "kind": "root", "meaning": "leap, spring"}, {"part": "-ent", "kind": "suffix", "meaning": "tending to"}], source: "Oxford 5000 / Cambridge EVP" , meaningVi: "kiên cường, có sức bật, có khả năng phục hồi nhanh sau khó khăn"},
    "meticulous": { level: "C1", pos: "adj", phonetic: "/məˈtɪk.jə.ləs/", meaning: "very careful and with great attention to every detail", example: "She kept meticulous notes on German verb prepositions.", synonyms: ["scrupulous", "thorough", "precise"], antonyms: ["careless", "sloppy"], morphology: [{"part": "metu (metus)", "kind": "root", "meaning": "fear, carefulness"}, {"part": "-culous (-ous)", "kind": "suffix", "meaning": "full of"}], source: "Cambridge EVP" , meaningVi: "tỉ mỉ, kỹ lưỡng, hết sức cẩn thận và chú ý đến từng chi tiết nhỏ"},
    "eloquent": { level: "C1", pos: "adj", phonetic: "/ˈel.ə.kwənt/", meaning: "giving a clear, strong message; fluent and persuasive in speaking or writing", example: "Reading C1 essays helps you become a more eloquent speaker.", synonyms: ["articulate", "expressive"], antonyms: ["inarticulate", "hesitant"], morphology: [{"part": "e- (ex-)", "kind": "prefix", "meaning": "out"}, {"part": "loqu (loqui)", "kind": "root", "meaning": "speak"}, {"part": "-ent", "kind": "suffix", "meaning": "characterized by"}], source: "Cambridge EVP" , meaningVi: "hùng hồn, lưu loát, có khả năng diễn đạt thuyết phục và truyền cảm"},
    "pragmatic": { level: "C1", pos: "adj", phonetic: "/præɡˈmæt.ɪk/", meaning: "solving problems in a sensible, practical way rather than following fixed theories", example: "We took a pragmatic approach to automating flashcard syntax.", synonyms: ["practical", "realistic"], antonyms: ["idealistic", "impractical"], morphology: [{"part": "pragma (prassein)", "kind": "root", "meaning": "deed, practical action"}, {"part": "-tic (-ic)", "kind": "suffix", "meaning": "pertaining to"}], source: "Oxford 5000 / Cambridge EVP" , meaningVi: "thực tế, thực dụng, giải quyết vấn đề theo hướng hợp lý và thực tiễn thay vì lý thuyết suông"},
    "scrutinize": { level: "C1", pos: "verb", phonetic: "/ˈskruː.tɪ.naɪz/", meaning: "to examine something very carefully in order to discover information", example: "Researchers scrutinize memory decay curves across thousands of learners.", synonyms: ["inspect", "examine", "analyze"], antonyms: ["glance", "overlook"], morphology: [{"part": "scrutini (scruta)", "kind": "root", "meaning": "search thoroughly, examine"}, {"part": "-ize", "kind": "suffix", "meaning": "make, perform"}], source: "Cambridge EVP" , meaningVi: "xem xét kỹ lưỡng, kiểm tra, soi xét thật cẩn thận để tìm thông tin"},
    "alleviate": { level: "C1", pos: "verb", phonetic: "/əˈliː.vi.eɪt/", meaning: "to make something bad such as pain or problems less severe", example: "Load balancing helps alleviate review spikes after busy weeks.", synonyms: ["ease", "mitigate", "relieve"], antonyms: ["aggravate", "worsen"], morphology: [{"part": "al- (ad-)", "kind": "prefix", "meaning": "to"}, {"part": "levi (levis)", "kind": "root", "meaning": "light in weight, ease"}, {"part": "-ate", "kind": "suffix", "meaning": "make, cause"}], source: "Oxford 5000 / Cambridge EVP" , meaningVi: "làm dịu bớt, giảm nhẹ, làm cho nỗi đau hoặc vấn đề bớt nghiêm trọng hơn"},
    "corroborate": { level: "C2", pos: "verb", phonetic: "/kəˈrɒb.ə.reɪt/", meaning: "to add proof to an account, statement, or theory with new information", example: "Neuroimaging studies corroborate the spacing effect in long-term potentiation.", synonyms: ["confirm", "substantiate", "verify"], antonyms: ["contradict", "refute"], morphology: [{"part": "cor- (com-)", "kind": "prefix", "meaning": "together, fully"}, {"part": "robor (robur)", "kind": "root", "meaning": "oak, strength"}, {"part": "-ate", "kind": "suffix", "meaning": "make, strengthen"}], source: "Cambridge EVP" , meaningVi: "củng cố, xác nhận, cung cấp thêm bằng chứng để chứng minh một nhận định"},
    "quintessential": { level: "C2", pos: "adj", phonetic: "/ˌkwɪn.tɪˈsen.ʃəl/", meaning: "being the most typical example or most important part of something", example: "Active recall is the quintessential technique for self-directed learning.", synonyms: ["archetypal", "classic", "prototypical"], antonyms: ["atypical", "uncharacteristic"], morphology: [{"part": "quint (quintus)", "kind": "prefix", "meaning": "fifth, highest"}, {"part": "essent (esse)", "kind": "root", "meaning": "essence, being"}, {"part": "-ial", "kind": "suffix", "meaning": "relating to"}], source: "Cambridge EVP" , meaningVi: "điển hình nhất, tinh túy nhất, đại diện tiêu biểu và hoàn hảo nhất cho cái gì"},
    "obfuscate": { level: "C2", pos: "verb", phonetic: "/ˈɒb.fʌs.keɪt/", meaning: "to make something less clear and harder to understand, especially intentionally", example: "Complex markup syntax should never obfuscate the knowledge being studied.", synonyms: ["obscure", "confuse", "muddy"], antonyms: ["clarify", "elucidate"], morphology: [{"part": "ob-", "kind": "prefix", "meaning": "over, against"}, {"part": "fusc (fuscus)", "kind": "root", "meaning": "dark, obscure"}, {"part": "-ate", "kind": "suffix", "meaning": "make, cause"}], source: "Cambridge EVP" , meaningVi: "làm rối rắm, che mờ, cố tình làm cho vấn đề trở nên khó hiểu"},
    "serendipity": { level: "C2", pos: "noun", phonetic: "/ˌser.ənˈdɪp.ə.ti/", meaning: "finding interesting or valuable things by chance", example: "Connecting notes across decks often leads to creative serendipity.", synonyms: ["chance", "fortuity"], antonyms: ["misfortune"], morphology: [{"part": "Serendip", "kind": "root", "meaning": "ancient Sri Lanka (fable of lucky princes)"}, {"part": "-ity", "kind": "suffix", "meaning": "quality, state"}], source: "Cambridge EVP" , meaningVi: "cơ duyên tình cờ, sự tình cờ phát hiện ra những điều thú vị hoặc giá trị"},

    // 4000 Essential English Words Vol. 5 (Units 01 - 04)
    "allot": {"level": "C1", "pos": "verb", "phonetic": "/əˈlɒt/", "meaning": "to give a particular share of time, money, or resources to someone or something", "example": "IELTS candidates should allot their time logically to achieve optimal results.", "collocations": ["allot time/resources - phân bổ thời gian/nguồn lực", "allot a portion - phân chia một phần"], "synonyms": ["allocate", "assign", "apportion"], "antonyms": ["withhold", "retain"], "morphology": [{"part": "al- (ad-)", "kind": "prefix", "meaning": "to, toward"}, {"part": "lot", "kind": "root", "meaning": "portion, share"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "chia, phân bổ, phân phối (thời gian, nguồn lực cho mục đích cụ thể)", "definitionEn": "to give a particular share of time, money, or resources to someone or something"},
    "appall": {"level": "C1", "pos": "verb", "phonetic": "/əˈpɔːl/", "meaning": "to shock or offend someone very much; to fill with horror or dismay", "example": "The horror movie was expected to appall audiences, but it proved to be a disappointment.", "collocations": ["appall the public - làm công chúng bàng hoàng", "be deeply appalled - cực kỳ phẫn nộ/kinh hãi"], "synonyms": ["horrify", "shock", "dismay"], "antonyms": ["delight", "reassure"], "morphology": [{"part": "ap- (ad-)", "kind": "prefix", "meaning": "to, toward"}, {"part": "pall (pallere)", "kind": "root", "meaning": "grow pale, terrify"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "làm kinh hãi, làm khiếp sợ, gây sốc", "definitionEn": "to shock or offend someone very much; to fill with horror or dismay"},
    "cache": {"level": "C2", "pos": "noun", "phonetic": "/kæʃ/", "meaning": "a hidden store of things such as weapons, treasure, or data kept for future use", "example": "When my brothers and I were young, we pretended to be ruthless pirates searching for a hidden cache of treasure.", "collocations": ["arms cache - kho vũ khí bí mật", "hidden cache - kho giấu kín"], "synonyms": ["hoard", "stash", "stockpile"], "antonyms": [], "morphology": [{"part": "cacher (coactare)", "kind": "root", "meaning": "press together, hide away"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "kho cất giấu, nơi cất giấu, kho bí mật (vũ khí, kho báu, dữ liệu)", "definitionEn": "a hidden store of things such as weapons, treasure, or data kept for future use"},
    "dearth": {"level": "C2", "pos": "noun", "phonetic": "/dɜːθ/", "meaning": "a severe shortage or lack of something that is needed", "example": "The young often suffer from a dearth of money but possess a plethora of time, whereas the elderly face the reverse.", "collocations": ["dearth of evidence - sự thiếu hụt bằng chứng", "dearth of resources - sự khan hiếm nguồn lực"], "synonyms": ["scarcity", "shortage", "paucity"], "antonyms": ["abundance", "plethora", "surplus"], "morphology": [{"part": "dear (deore)", "kind": "root", "meaning": "costly, scarce"}, {"part": "-th", "kind": "suffix", "meaning": "state, condition"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "sự khan hiếm, sự thiếu hụt nghiêm trọng", "definitionEn": "a severe shortage or lack of something that is needed"},
    "deliberate": {"level": "C1", "pos": "adj", "phonetic": "/dɪˈlɪb.ər.ət/", "meaning": "done intentionally and carefully planned rather than by accident", "example": "Every effort I make to improve my English proficiency is deliberate and strategic.", "collocations": ["deliberate attempt - nỗ lực có chủ đích", "deliberate choice - lựa chọn có cân nhắc"], "synonyms": ["intentional", "calculated", "purposeful"], "antonyms": ["accidental", "hasty", "unintentional"], "morphology": [{"part": "de-", "kind": "prefix", "meaning": "completely"}, {"part": "librare (libra)", "kind": "root", "meaning": "weigh, balance"}, {"part": "-ate", "kind": "suffix", "meaning": "characterized by"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "cố ý, có chủ đích, được tính toán cẩn thận", "definitionEn": "done intentionally and carefully planned rather than by accident"},
    "dire": {"level": "C1", "pos": "adj", "phonetic": "/ˈdaɪər/", "meaning": "extremely serious, urgent, or terrible in consequence", "example": "Most natural disasters cause dire consequences that society struggles to mitigate.", "collocations": ["dire consequences - hậu quả thảm khốc", "in dire need - trong tình thế cấp thiết"], "synonyms": ["dreadful", "catastrophic", "grave"], "antonyms": ["favorable", "mild", "trivial"], "morphology": [{"part": "dirus", "kind": "root", "meaning": "fearful, ominous, dreadful"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "thảm khốc, khốc liệt, vô cùng tồi tệ", "definitionEn": "extremely serious, urgent, or terrible in consequence"},
    "elapse": {"level": "C1", "pos": "verb", "phonetic": "/ɪˈlæps/", "meaning": "(of time) to pass or go by", "example": "Few realize how quickly time will elapse turning cherished memories into distant history.", "collocations": ["time elapses - thời gian trôi qua", "years elapse - nhiều năm trôi qua"], "synonyms": ["pass", "expire", "go by"], "antonyms": ["halt", "linger"], "morphology": [{"part": "e- (ex-)", "kind": "prefix", "meaning": "out, away"}, {"part": "laps (labi)", "kind": "root", "meaning": "glide, slip, pass"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "trôi qua (dùng cho thời gian)", "definitionEn": "(of time) to pass or go by"},
    "empathy": {"level": "B2", "pos": "noun", "phonetic": "/ˈem.pə.θi/", "meaning": "the ability to understand and share the feelings and experiences of another person", "example": "Some individuals lack empathy for others, appearing entirely indifferent to their suffering.", "collocations": ["demonstrate empathy - thể hiện sự thấu cảm", "empathy towards someone - sự đồng cảm dành cho ai"], "synonyms": ["compassion", "understanding", "affinity"], "antonyms": ["apathy", "indifference"], "morphology": [{"part": "em- (en-)", "kind": "prefix", "meaning": "in, into"}, {"part": "path (pathos)", "kind": "root", "meaning": "feeling, emotion"}, {"part": "-y", "kind": "suffix", "meaning": "quality, state"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "sự đồng cảm, sự thấu cảm (khả năng hiểu và chia sẻ cảm xúc)", "definitionEn": "the ability to understand and share the feelings and experiences of another person"},
    "fanciful": {"level": "C2", "pos": "adj", "phonetic": "/ˈfæn.sɪ.fəl/", "meaning": "imagined rather than based on realistic facts; overly whimsical or unrealistic", "example": "Some of my career plans are purely fanciful rather than rooted in practical reality.", "collocations": ["fanciful idea - ý tưởng viển vông", "fanciful notion - khái niệm xa rời thực tế"], "synonyms": ["whimsical", "imaginative", "unrealistic"], "antonyms": ["practical", "realistic", "pragmatic"], "morphology": [{"part": "fancy (phantasia)", "kind": "root", "meaning": "imagination, fantasy"}, {"part": "-ful", "kind": "suffix", "meaning": "full of"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "viển vông, kỳ lạ, tưởng tượng không thực tế", "definitionEn": "imagined rather than based on realistic facts; overly whimsical or unrealistic"},
    "gripe": {"level": "C2", "pos": "verb", "phonetic": "/ɡraɪp/", "meaning": "to complain continually about something, especially something minor", "example": "My mother will constantly gripe whenever I neglect my daily household chores.", "collocations": ["gripe about something - phàn nàn về điều gì", "gripe continuously - cằn nhằn không ngừng"], "synonyms": ["grumble", "complain", "whine"], "antonyms": ["praise", "commend"], "morphology": [{"part": "gripan", "kind": "root", "meaning": "clutch, pinch, complain"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "cằn nhằn, phàn nàn (thường về những điều nhỏ nhặt)", "definitionEn": "to complain continually about something, especially something minor"},
    "gruelling": {"level": "C2", "pos": "adj", "phonetic": "/ˈɡruː.ə.lɪŋ/", "meaning": "extremely tiring, demanding, and difficult to endure", "example": "Professional mountain climbers must endure a gruelling training regimen before attempting high peaks.", "collocations": ["gruelling schedule - lịch trình kiệt sức", "gruelling journey - hành trình gian khổ"], "synonyms": ["exhausting", "arduous", "strenuous"], "antonyms": ["effortless", "easy"], "morphology": [{"part": "gruel", "kind": "root", "meaning": "exhaust, punish severely"}, {"part": "-ing", "kind": "suffix", "meaning": "causing, participial adj"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "cam go, kiệt sức, đòi hỏi nhiều sức lực và sự chịu đựng", "definitionEn": "extremely tiring, demanding, and difficult to endure"},
    "mundane": {"level": "C1", "pos": "adj", "phonetic": "/mʌnˈdeɪn/", "meaning": "very ordinary and therefore not interesting or exciting", "example": "Working in a purely mundane job without any creative freedom would drive me insane.", "collocations": ["mundane tasks - công việc tẻ nhạt hằng ngày", "mundane reality - thực tại tầm thường"], "synonyms": ["humdrum", "banal", "ordinary"], "antonyms": ["extraordinary", "exciting", "sublime"], "morphology": [{"part": "mund (mundus)", "kind": "root", "meaning": "world, earthly"}, {"part": "-ane", "kind": "suffix", "meaning": "belonging to"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "tẻ nhạt, bình thường, thuộc về đời thường trần tục", "definitionEn": "very ordinary and therefore not interesting or exciting"},
    "opt": {"level": "B2", "pos": "verb", "phonetic": "/ɒpt/", "meaning": "to make a choice from a range of possibilities", "example": "While many prioritize financial security, I would still opt for love regardless of the sacrifices required.", "collocations": ["opt for something - chọn cái gì", "opt to do something - quyết định làm gì"], "synonyms": ["choose", "select", "decide"], "antonyms": ["reject", "refuse"], "morphology": [{"part": "opt (optare)", "kind": "root", "meaning": "choose, wish, select"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "lựa chọn, chọn lựa (sau khi cân nhắc các phương án)", "definitionEn": "to make a choice from a range of possibilities"},
    "outrage": {"level": "B2", "pos": "noun", "phonetic": "/ˈaʊt.reɪdʒ/", "meaning": "a strong feeling of shock and anger caused by something unfair or cruel", "example": "Hank could not conceal his outrage when falsely accused of stealing food.", "collocations": ["spark public outrage - gây ra sự phẫn nộ trong công chúng", "express outrage - bày tỏ sự giận dữ"], "synonyms": ["indignation", "fury", "wrath"], "antonyms": ["delight", "calm", "satisfaction"], "morphology": [{"part": "outre (ultra)", "kind": "prefix", "meaning": "beyond bounds"}, {"part": "-age", "kind": "suffix", "meaning": "action, condition"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "sự phẫn nộ, sự giận dữ tột cùng", "definitionEn": "a strong feeling of shock and anger caused by something unfair or cruel"},
    "paltry": {"level": "C2", "pos": "adj", "phonetic": "/ˈpɔːl.tri/", "meaning": "(of an amount of money or resources) very small and of little or no value", "example": "They offered him a paltry sum of money that barely covered his travel expenses.", "collocations": ["paltry sum - số tiền bèo bọt", "paltry amount - lượng ít ỏi"], "synonyms": ["meager", "trifling", "negligible"], "antonyms": ["substantial", "generous", "ample"], "morphology": [{"part": "palt", "kind": "root", "meaning": "rag, scrap, worthless thing"}, {"part": "-ry", "kind": "suffix", "meaning": "characterized by"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "ít ỏi, bèo bọt, không đáng kể", "definitionEn": "(of an amount of money or resources) very small and of little or no value"},
    "rectify": {"level": "C1", "pos": "verb", "phonetic": "/ˈrek.tɪ.faɪ/", "meaning": "to correct something that is wrong or put a mistake right", "example": "We apologize for the inconvenience caused and are taking immediate steps to rectify the situation.", "collocations": ["rectify an error - khắc phục một sai sót", "rectify a situation - chấn chỉnh/sửa chữa tình hình"], "synonyms": ["correct", "remedy", "amend"], "antonyms": ["worsen", "damage", "corrupt"], "morphology": [{"part": "rect (rectus)", "kind": "root", "meaning": "straight, right"}, {"part": "-ify", "kind": "suffix", "meaning": "make, cause to be"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "khắc phục, sửa chữa, chấn chỉnh (sai sót, tình huống)", "definitionEn": "to correct something that is wrong or put a mistake right"},
    "resourceful": {"level": "C1", "pos": "adj", "phonetic": "/rɪˈzɔː.sfəl/", "meaning": "skilled at finding clever and practical ways to overcome difficulties", "example": "A resourceful manager can find creative solutions even when facing tight budget constraints.", "collocations": ["resourceful person - người tháo vát", "highly resourceful - cực kỳ linh hoạt/tháo vát"], "synonyms": ["ingenious", "inventive", "capable"], "antonyms": ["helpless", "unimaginative"], "morphology": [{"part": "re-", "kind": "prefix", "meaning": "again, back"}, {"part": "source (surgere)", "kind": "root", "meaning": "rise, spring forth"}, {"part": "-ful", "kind": "suffix", "meaning": "full of, ingenious"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "tháo vát, linh hoạt, xoay xở giỏi", "definitionEn": "skilled at finding clever and practical ways to overcome difficulties"},
    "sustenance": {"level": "C2", "pos": "noun", "phonetic": "/ˈsʌs.tən.əns/", "meaning": "food and drink needed to stay alive and healthy; means of livelihood", "example": "My part-time tutoring job barely provides enough income for basic sustenance.", "collocations": ["basic sustenance - kế sinh nhai cơ bản", "draw sustenance from - lấy nguồn sống từ"], "synonyms": ["nourishment", "livelihood", "subsistence"], "antonyms": ["starvation", "deprivation"], "morphology": [{"part": "sus- (sub-)", "kind": "prefix", "meaning": "up from below"}, {"part": "ten (tenere)", "kind": "root", "meaning": "hold, support"}, {"part": "-ance", "kind": "suffix", "meaning": "state, means of"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "thực phẩm nuôi sống, kế sinh nhai, sự duy trì cuộc sống", "definitionEn": "food and drink needed to stay alive and healthy; means of livelihood"},
    "tedious": {"level": "C1", "pos": "adj", "phonetic": "/ˈtiː.di.əs/", "meaning": "lasting too long and not interesting; monotonous and tiresome", "example": "Preparing lesson plans manually can be so tedious that teachers often delegate the task to AI models.", "collocations": ["tedious process - quy trình tẻ nhạt", "tedious task - công việc chán ngắt"], "synonyms": ["monotonous", "tiresome", "dreary"], "antonyms": ["engaging", "stimulating", "exciting"], "morphology": [{"part": "tedi (taedium)", "kind": "root", "meaning": "weariness, boredom"}, {"part": "-ous", "kind": "suffix", "meaning": "full of"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "chán ngắt, tẻ nhạt, rườm rà và kéo dài", "definitionEn": "lasting too long and not interesting; monotonous and tiresome"},
    "abbey": {"level": "B2", "pos": "noun", "phonetic": "/ˈæb.i/", "meaning": "a large church together with a group of buildings where monks or nuns live", "example": "An abbey is a large building where monks or nuns live, whereas a monastery is typically for monks and a convent for nuns.", "collocations": ["historic abbey - tu viện cổ kính", "abbey church - nhà thờ tu viện"], "synonyms": ["monastery", "convent", "priory"], "antonyms": [], "morphology": [{"part": "abba", "kind": "root", "meaning": "father, abbot"}, {"part": "-ey (-ia)", "kind": "suffix", "meaning": "place, jurisdiction"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "tu viện, đại tu viện (nơi các tu sĩ hoặc nữ tu sinh sống và tu tập)", "definitionEn": "a large church together with a group of buildings where monks or nuns live"},
    "abundant": {"level": "C1", "pos": "adj", "phonetic": "/əˈbʌn.dənt/", "meaning": "existing or available in large quantities; more than enough", "example": "My budget for gaming is abundant whereas others are struggling to allocate their resources properly.", "collocations": ["abundant evidence - bằng chứng dồi dào", "abundant supply - nguồn cung dồi dào"], "synonyms": ["plentiful", "copious", "bountiful"], "antonyms": ["scarce", "sparse", "meager"], "morphology": [{"part": "ab-", "kind": "prefix", "meaning": "from, away"}, {"part": "und (unda)", "kind": "root", "meaning": "wave, overflow"}, {"part": "-ant", "kind": "suffix", "meaning": "being, characterized by"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "dồi dào, phong phú, nhiều hơn mức đủ dùng", "definitionEn": "existing or available in large quantities; more than enough"},
    "adjoin": {"level": "C2", "pos": "verb", "phonetic": "/əˈdʒɔɪn/", "meaning": "to be very near, next to, or touching another building, room, or area", "example": "My house does not adjoin any other properties in the neighborhood.", "collocations": ["adjoin a building - tiếp giáp một tòa nhà", "directly adjoin - tiếp giáp trực tiếp"], "synonyms": ["border", "abut", "touch"], "antonyms": ["separate", "detach"], "morphology": [{"part": "ad-", "kind": "prefix", "meaning": "to, toward"}, {"part": "join (jungere)", "kind": "root", "meaning": "connect, link together"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "sát vách, tiếp giáp, nằm ngay bên cạnh", "definitionEn": "to be very near, next to, or touching another building, room, or area"},
    "ample": {"level": "C1", "pos": "adj", "phonetic": "/ˈæm.pəl/", "meaning": "enough or more than enough; plentiful and generous in scope", "example": "Due to poor time management, I do not have ample time to complete my course assignments.", "collocations": ["ample time - thời gian dư dả", "ample opportunity - cơ hội rộng mở"], "synonyms": ["plentiful", "sufficient", "generous"], "antonyms": ["insufficient", "meager", "scant"], "morphology": [{"part": "amplus", "kind": "root", "meaning": "large, spacious, abundant"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "dư dả, rộng rãi, thừa đủ cho một nhu cầu cụ thể", "definitionEn": "enough or more than enough; plentiful and generous in scope"},
    "arid": {"level": "C1", "pos": "adj", "phonetic": "/ˈær.ɪd/", "meaning": "having very little rain and therefore extremely dry and barren", "example": "Summer heat makes the desert even more arid than ever.", "collocations": ["arid climate - khí hậu khô cằn", "arid region - vùng khô cằn"], "synonyms": ["parched", "barren", "dry"], "antonyms": ["fertile", "humid", "lush"], "morphology": [{"part": "ar (arere)", "kind": "root", "meaning": "be dry, parched"}, {"part": "-id", "kind": "suffix", "meaning": "characterized by"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "khô cằn, hoang vu (khí hậu hoặc đất đai vô cùng khô do rất ít mưa)", "definitionEn": "having very little rain and therefore extremely dry and barren"},
    "deprive": {"level": "C1", "pos": "verb", "phonetic": "/dɪˈpraɪv/", "meaning": "to take something important or necessary away from someone", "example": "Her tedious job would deprive her of any enjoyment in life.", "collocations": ["deprive somebody of something - tước đoạt cái gì của ai", "sleep deprived - bị thiếu ngủ"], "synonyms": ["strip", "divest", "bereave"], "antonyms": ["provide", "endow", "supply"], "morphology": [{"part": "de-", "kind": "prefix", "meaning": "completely, away"}, {"part": "priv (privare)", "kind": "root", "meaning": "strip, take away"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "tước đoạt, lấy đi, không cho ai hưởng cái gì thiết yếu", "definitionEn": "to take something important or necessary away from someone"},
    "drought": {"level": "B2", "pos": "noun", "phonetic": "/draʊt/", "meaning": "a long period when there is little or no rain, causing water shortages", "example": "The drought in Vietnam usually lasts for three months, from March to June.", "collocations": ["severe drought - hạn hán nghiêm trọng", "drought-stricken - bị hạn hán tàn phá"], "synonyms": ["aridity", "dry spell", "water shortage"], "antonyms": ["deluge", "flood", "monsoon"], "morphology": [{"part": "drug (dragan)", "kind": "root", "meaning": "dry, parched"}, {"part": "-th (-t)", "kind": "suffix", "meaning": "state, condition"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "trận hạn hán, tình trạng khô hạn kéo dài", "definitionEn": "a long period when there is little or no rain, causing water shortages"},
    "eligible": {"level": "B2", "pos": "adj", "phonetic": "/ˈel.ɪ.dʒə.bəl/", "meaning": "having the necessary qualifications or meeting the conditions to do or receive something", "example": "Those who bought tickets are eligible to enter the venue.", "collocations": ["eligible for something - đủ điều kiện hưởng cái gì", "eligible to do something - đủ điều kiện làm gì"], "synonyms": ["qualified", "entitled", "suitable"], "antonyms": ["ineligible", "disqualified", "unfit"], "morphology": [{"part": "e- (ex-)", "kind": "prefix", "meaning": "out"}, {"part": "lig (legere)", "kind": "root", "meaning": "choose, select"}, {"part": "-ible", "kind": "suffix", "meaning": "able to be"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "đủ điều kiện, đủ tư cách, hợp pháp (theo quy định)", "definitionEn": "having the necessary qualifications or meeting the conditions to do or receive something"},
    "fast": {"level": "B2", "pos": "verb", "phonetic": "/fæst/", "meaning": "to eat no food for a period of time, often for religious or health reasons", "example": "Sometimes I decide to fast for a day to feel less guilty about overeating.", "collocations": ["fast for a day - nhịn ăn một ngày", "intermittent fasting - nhịn ăn gián đoạn"], "synonyms": ["abstain", "go hungry", "diet"], "antonyms": ["feast", "gorge", "indulge"], "morphology": [{"part": "fastan", "kind": "root", "meaning": "hold firmly, abstain from food"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "nhịn ăn, ăn chay (trong một khoảng thời gian)", "definitionEn": "to eat no food for a period of time, often for religious or health reasons"},
    "grumble": {"level": "C1", "pos": "verb", "phonetic": "/ˈɡrʌm.bəl/", "meaning": "to complain about someone or something in a bad-tempered or low voice", "example": "Every morning, I grumble about getting up early and going to work.", "collocations": ["grumble about something - càu nhàu về điều gì", "grumble constantly - càu nhàu liên tục"], "synonyms": ["complain", "mutter", "gripe"], "antonyms": ["compliment", "rejoice"], "morphology": [{"part": "grum", "kind": "root", "meaning": "murmur, growl low"}, {"part": "-ble (-le)", "kind": "suffix", "meaning": "frequentative action"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "càu nhàu, lầm bầm phàn nàn (trong miệng hoặc với giọng bực bội)", "definitionEn": "to complain about someone or something in a bad-tempered or low voice"},
    "inland": {"level": "B2", "pos": "adv", "phonetic": "/ˈɪn.lənd/", "meaning": "in or toward the interior of a country, away from the coast", "example": "The storm is moving inland, threatening severe destruction to lives and property.", "collocations": ["move inland - di chuyển vào đất liền", "inland area - khu vực nội địa"], "synonyms": ["interior", "upcountry", "domestic"], "antonyms": ["coastal", "maritime", "offshore"], "morphology": [{"part": "in-", "kind": "prefix", "meaning": "within, inside"}, {"part": "land", "kind": "root", "meaning": "interior territory"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "vào nội địa, vào trong đất liền, hướng về vùng nội địa", "definitionEn": "in or toward the interior of a country, away from the coast"},
    "moisture": {"level": "B2", "pos": "noun", "phonetic": "/ˈmɔɪs.tʃər/", "meaning": "very small drops of water present in the air, on a surface, or in the ground", "example": "Some couples express their affection by breathing on a window pane and drawing a heart in the moisture.", "collocations": ["retain moisture - giữ ẩm", "moisture content - hàm lượng độ ẩm"], "synonyms": ["dampness", "humidity", "condensation"], "antonyms": ["dryness", "aridity"], "morphology": [{"part": "moist (mucidus)", "kind": "root", "meaning": "slightly wet, damp"}, {"part": "-ure", "kind": "suffix", "meaning": "state, result"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "hơi ẩm, độ ẩm (giọt nước nhỏ đọng lại trong không khí hoặc trên bề mặt)", "definitionEn": "very small drops of water present in the air, on a surface, or in the ground"},
    "nonetheless": {"level": "C1", "pos": "adv", "phonetic": "/ˌnʌn.ðəˈles/", "meaning": "despite what has just been said; nevertheless", "example": "His life is gruelling; nonetheless, he still pushes forward with resolute effort.", "collocations": ["nonetheless important - tuy vậy vẫn quan trọng", "but nonetheless - nhưng dù sao thì"], "synonyms": ["nevertheless", "however", "regardless"], "antonyms": ["consequently", "therefore"], "morphology": [{"part": "none", "kind": "prefix", "meaning": "not at all"}, {"part": "the", "kind": "root", "meaning": "by that much"}, {"part": "-less", "kind": "suffix", "meaning": "less, in spite of that"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "tuy nhiên, dù sao thì, mặc dù vậy", "definitionEn": "despite what has just been said; nevertheless"},
    "oath": {"level": "C1", "pos": "noun", "phonetic": "/əʊθ/", "meaning": "a formal and solemn promise, especially to tell the truth or fulfill a duty", "example": "Medical students must swear the Hippocratic oath to dedicate their lives to healing others.", "collocations": ["take an oath - tuyên thệ", "under oath - dưới lời tuyên thệ"], "synonyms": ["vow", "pledge", "sworn promise"], "antonyms": ["breach", "betrayal"], "morphology": [{"part": "ath (aito-)", "kind": "root", "meaning": "solemn vow, sworn pledge"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "lời thề, lời tuyên thệ trang trọng", "definitionEn": "a formal and solemn promise, especially to tell the truth or fulfill a duty"},
    "prairie": {"level": "C2", "pos": "noun", "phonetic": "/ˈpreə.ri/", "meaning": "a wide, flat, treeless area of grassland, especially in North America", "example": "Vietnam does not have any vast prairie as it is situated in a tropical climate region.", "collocations": ["vast prairie - thảo nguyên bao la", "prairie ecosystem - hệ sinh thái thảo nguyên"], "synonyms": ["grassland", "savanna", "steppe"], "antonyms": ["forest", "mountain"], "morphology": [{"part": "prat (pratum)", "kind": "root", "meaning": "meadow, grassland"}, {"part": "-rie (-aria)", "kind": "suffix", "meaning": "expanse, domain"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "thảo nguyên, đồng cỏ rộng lớn", "definitionEn": "a wide, flat, treeless area of grassland, especially in North America"},
    "ragged": {"level": "C1", "pos": "adj", "phonetic": "/ˈræɡ.ɪd/", "meaning": "(of clothes or fabric) old, torn, and in poor condition", "example": "My clothes are ragged, yet I still spend most of my money on video games.", "collocations": ["ragged clothes - quần áo rách rưới", "ragged edge - mép nham nhở"], "synonyms": ["tattered", "frayed", "shabby"], "antonyms": ["neat", "immaculate", "intact"], "morphology": [{"part": "rag", "kind": "root", "meaning": "torn cloth, tatter"}, {"part": "-ed", "kind": "suffix", "meaning": "having, characterized by"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "rách rưới, tả tơi, cũ nát (dùng cho quần áo, vải vóc)", "definitionEn": "(of clothes or fabric) old, torn, and in poor condition"},
    "rugged": {"level": "C1", "pos": "adj", "phonetic": "/ˈrʌɡ.ɪd/", "meaning": "(of land or terrain) rocky, uneven, and difficult to travel over", "example": "Teachers in mountainous areas must travel on rugged roads to inspire their students.", "collocations": ["rugged terrain - địa hình hiểm trở", "rugged coastline - bờ biển gồ ghề"], "synonyms": ["jagged", "craggy", "rough"], "antonyms": ["smooth", "even", "delicate"], "morphology": [{"part": "rug", "kind": "root", "meaning": "rough, uneven rock"}, {"part": "-ed", "kind": "suffix", "meaning": "characterized by"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "gồ ghề, lởm chởm, hiểm trở (địa hình khó di chuyển)", "definitionEn": "(of land or terrain) rocky, uneven, and difficult to travel over"},
    "scarce": {"level": "C1", "pos": "adj", "phonetic": "/skeəs/", "meaning": "not easy to find or obtain; existing in insufficient quantity", "example": "Due to the conflict, gasoline has become scarce as imports have dropped sharply.", "collocations": ["scarce resources - tài nguyên khan hiếm", "make oneself scarce - lén rút lui, chuồn mất"], "synonyms": ["rare", "scant", "sparse"], "antonyms": ["abundant", "plentiful", "ample"], "morphology": [{"part": "ex-", "kind": "prefix", "meaning": "out"}, {"part": "carpsus (carpere)", "kind": "root", "meaning": "plucked out, restricted"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "khan hiếm, ít ỏi, không đủ cho nhu cầu", "definitionEn": "not easy to find or obtain; existing in insufficient quantity"},
    "speculate": {"level": "C1", "pos": "verb", "phonetic": "/ˈspek.jə.leɪt/", "meaning": "to form opinions or guesses about something without having complete evidence", "example": "Some exam questions are extremely challenging, forcing me to speculate before time runs out.", "collocations": ["speculate about something - suy đoán về điều gì", "wildly speculate - suy đoán vô căn cứ"], "synonyms": ["conjecture", "theorize", "hypothesize"], "antonyms": ["verify", "prove", "confirm"], "morphology": [{"part": "specul (specere)", "kind": "root", "meaning": "look, observe, spy"}, {"part": "-ate", "kind": "suffix", "meaning": "perform, form theory"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "suy đoán, đoán mò, đưa ra giả định khi chưa có bằng chứng chắc chắn", "definitionEn": "to form opinions or guesses about something without having complete evidence"},
    "analytic": {"level": "C1", "pos": "adj", "phonetic": "/ˌæn.əˈlɪt.ɪk/", "meaning": "examining things very carefully using logical and systematic reasoning", "example": "The report is so analytic that it provides clear insights into complex data.", "collocations": ["analytical depth - độ sâu phân tích", "analytical mindset - tư duy phân tích"], "synonyms": ["logical", "systematic", "investigative"], "antonyms": ["synthetic", "unsystematic"], "morphology": [{"part": "ana-", "kind": "prefix", "meaning": "up, throughout"}, {"part": "lyt (lyein)", "kind": "root", "meaning": "loosen, break down"}, {"part": "-ic", "kind": "suffix", "meaning": "pertaining to"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "có tính phân tích, sử dụng phương pháp phân tích suy luận", "definitionEn": "examining things very carefully using logical and systematic reasoning"},
    "assert": {"level": "C1", "pos": "verb", "phonetic": "/əˈsɜːt/", "meaning": "to state clearly and firmly that something is true", "example": "After having assert that the Earth was flat, he felt deeply humiliated.", "collocations": ["assert authority - khẳng định quyền lực", "boldly assert - dũng cảm khẳng định"], "synonyms": ["declare", "affirm", "maintain"], "antonyms": ["deny", "retract", "refute"], "morphology": [{"part": "as- (ad-)", "kind": "prefix", "meaning": "to, toward"}, {"part": "sert (serere)", "kind": "root", "meaning": "join, declare, claim"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "khẳng định, quả quyết, tuyên bố chắc chắn", "definitionEn": "to state clearly and firmly that something is true"},
    "bachelor": {"level": "B2", "pos": "noun", "phonetic": "/ˈbætʃ.əl.ər/", "meaning": "an unmarried man; or a person who holds a first university degree", "example": "After remaining a bachelor into his late twenties, Tom finally settled down with a loving partner.", "collocations": ["eligible bachelor - người độc thân sáng giá", "remain a bachelor - giữ tình trạng độc thân"], "synonyms": ["single man", "unmarried man"], "antonyms": ["husband", "married man"], "morphology": [{"part": "baccalaur", "kind": "root", "meaning": "young knight, unmarried graduate"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "người đàn ông chưa vợ, người độc thân; bằng cử nhân", "definitionEn": "an unmarried man; or a person who holds a first university degree"},
    "calculus": {"level": "C2", "pos": "noun", "phonetic": "/ˈkæl.kjə.ləs/", "meaning": "a branch of mathematics that deals with rates of change and continuous quantities", "example": "Majoring in English allowed me to avoid calculus, a subject I always struggled with.", "collocations": ["differential calculus - giải tích vi phân", "grasp calculus - hiểu/nắm vững giải tích"], "synonyms": ["mathematical analysis", "infinitesimal math"], "antonyms": [], "morphology": [{"part": "calc (calx)", "kind": "root", "meaning": "limestone, counting pebble"}, {"part": "-ulus", "kind": "suffix", "meaning": "diminutive (small stone)"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "môn giải tích, phép tính giải tích (phân nhánh toán học nghiên cứu sự thay đổi)", "definitionEn": "a branch of mathematics that deals with rates of change and continuous quantities"},
    "celestial": {"level": "C2", "pos": "adj", "phonetic": "/səˈles.ti.əl/", "meaning": "of or relating to the sky, heaven, or outer space", "example": "Scientists fear that a massive celestial body colliding with Earth could wipe out all life.", "collocations": ["celestial body - thiên thể", "celestial navigation - dẫn đường bằng thiên văn"], "synonyms": ["heavenly", "astronomical", "cosmic"], "antonyms": ["terrestrial", "earthly", "mundane"], "morphology": [{"part": "celest (caelum)", "kind": "root", "meaning": "heaven, sky"}, {"part": "-ial", "kind": "suffix", "meaning": "relating to"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "thuộc vũ trụ, thuộc về bầu trời, thuộc về vũ trụ", "definitionEn": "of or relating to the sky, heaven, or outer space"},
    "cognitive": {"level": "C1", "pos": "adj", "phonetic": "/ˈkɒɡ.nə.tɪv/", "meaning": "connected with mental processes of understanding, thinking, and learning", "example": "Decision-making is a complex cognitive process that occurs before one forms a final opinion.", "collocations": ["cognitive process - tiến trình nhận thức", "cognitive impairment - suy giảm nhận thức"], "synonyms": ["mental", "intellectual", "perceptual"], "antonyms": ["physical", "visceral"], "morphology": [{"part": "co- (com-)", "kind": "prefix", "meaning": "together, fully"}, {"part": "gnit (gnoscere)", "kind": "root", "meaning": "know, perceive"}, {"part": "-ive", "kind": "suffix", "meaning": "relating to"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "thuộc về nhận thức, liên quan đến tư duy và trí tuệ", "definitionEn": "connected with mental processes of understanding, thinking, and learning"},
    "collision": {"level": "B2", "pos": "noun", "phonetic": "/kəˈlɪʒ.ən/", "meaning": "an accident or event in which two or more objects or vehicles crash into each other", "example": "A catastrophic mid-air collision occurred due to miscommunication with air traffic control.", "collocations": ["mid-air collision - va chạm trên không", "head-on collision - va chạm trực diện"], "synonyms": ["crash", "impact", "clash"], "antonyms": ["avoidance", "harmony"], "morphology": [{"part": "col- (com-)", "kind": "prefix", "meaning": "together"}, {"part": "lis (laedere)", "kind": "root", "meaning": "strike, dash"}, {"part": "-ion", "kind": "suffix", "meaning": "act, state"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "vụ va chạm, sự đụng độ giữa các phương tiện", "definitionEn": "an accident or event in which two or more objects or vehicles crash into each other"},
    "competent": {"level": "C1", "pos": "adj", "phonetic": "/ˈkɒm.pɪ.tənt/", "meaning": "able to do something well and effectively; having the required skill", "example": "She is highly competent, earning admission to one of the most prestigious universities.", "collocations": ["highly competent - rất có năng lực", "academically competent - có năng lực học thuật"], "synonyms": ["capable", "proficient", "qualified"], "antonyms": ["incompetent", "inept", "unqualified"], "morphology": [{"part": "com-", "kind": "prefix", "meaning": "together"}, {"part": "pet (petere)", "kind": "root", "meaning": "strive, be fit/suitable"}, {"part": "-ent", "kind": "suffix", "meaning": "being, capable"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "có năng lực, thành thạo, đủ khả năng làm tốt nhiệm vụ", "definitionEn": "able to do something well and effectively; having the required skill"},
    "diploma": {"level": "B1", "pos": "noun", "phonetic": "/dɪˈpləʊ.mə/", "meaning": "an official document certifying that someone has completed a course of study", "example": "After obtaining my diploma, I felt aimless due to the lack of a clear career plan.", "collocations": ["obtain a diploma - nhận/lấy bằng", "high school diploma - bằng tốt nghiệp trung học"], "synonyms": ["certificate", "degree", "credential"], "antonyms": [], "morphology": [{"part": "diplo (diploun)", "kind": "root", "meaning": "double, fold paper"}, {"part": "-ma", "kind": "suffix", "meaning": "official document"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "bằng cấp, chứng chỉ (do trường phổ thông hoặc cao đẳng/đại học cấp)", "definitionEn": "an official document certifying that someone has completed a course of study"},
    "excel": {"level": "C1", "pos": "verb", "phonetic": "/ɪkˈsel/", "meaning": "to be extremely good at doing something or to surpass others", "example": "My parents excel at public speaking, captivating audiences for hours without fatigue.", "collocations": ["excel in/at - xuất sắc về", "excel academically - học tập xuất sắc"], "synonyms": ["shine", "surpass", "outperform"], "antonyms": ["fail", "flounder", "lag"], "morphology": [{"part": "ex-", "kind": "prefix", "meaning": "out, beyond"}, {"part": "cel (cellere)", "kind": "root", "meaning": "rise high, surpass"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "cực kỳ giỏi, xuất sắc trong một lĩnh vực cụ thể", "definitionEn": "to be extremely good at doing something or to surpass others"},
    "geology": {"level": "B2", "pos": "noun", "phonetic": "/dʒiˈɒl.ə.dʒi/", "meaning": "the scientific study of the Earth's physical structure, rocks, and history", "example": "In my view, geology seems tedious because it revolves primarily around analyzing rock formations.", "collocations": ["field of geology - lĩnh vực địa chất", "structural geology - địa chất cấu tạo"], "synonyms": ["earth science", "lithology"], "antonyms": [], "morphology": [{"part": "geo- (ge)", "kind": "prefix", "meaning": "earth, ground"}, {"part": "-logy (logos)", "kind": "suffix", "meaning": "science, study of"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "ngành địa chất học (nghiên cứu cấu trúc và lịch sử Trái Đất)", "definitionEn": "the scientific study of the Earth's physical structure, rocks, and history"},
    "harness": {"level": "C1", "pos": "verb", "phonetic": "/ˈhɑː.nəs/", "meaning": "to control and use the force or strength of something to produce power or achieve a result", "example": "The hydroelectric dam harness the power of water to generate electricity for nearby cities.", "collocations": ["harness energy - khai thác năng lượng", "harness natural resources - khai thác tài nguyên thiên nhiên"], "synonyms": ["utilize", "exploit", "channel"], "antonyms": ["waste", "squander"], "morphology": [{"part": "harneis", "kind": "root", "meaning": "gear, equip, utilize power"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "khai thác, tận dụng (nguồn năng lượng, sức mạnh)", "definitionEn": "to control and use the force or strength of something to produce power or achieve a result"},
    "intellect": {"level": "C1", "pos": "noun", "phonetic": "/ˈɪn.təl.ekt/", "meaning": "the ability to think logically, understand complex ideas, and reason at a high level", "example": "Dolphins possess a remarkable intellect, enabling them to communicate in sophisticated ways.", "collocations": ["remarkable intellect - trí tuệ phi thường", "keen intellect - trí tuệ sắc sảo"], "synonyms": ["intelligence", "mind", "reason"], "antonyms": ["ignorance", "folly"], "morphology": [{"part": "intel- (inter-)", "kind": "prefix", "meaning": "between, among"}, {"part": "lect (legere)", "kind": "root", "meaning": "choose, discern, understand"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "trí tuệ, khả năng tư duy và hiểu biết cấp cao", "definitionEn": "the ability to think logically, understand complex ideas, and reason at a high level"},
    "keen": {"level": "C1", "pos": "adj", "phonetic": "/kiːn/", "meaning": "very interested, eager, or enthusiastic; or having a sharp mind or edge", "example": "I lack the keen judgment required to make rapid decisions under pressure.", "collocations": ["keen judgment - sự phán đoán sắc sảo", "keen eye for detail - mắt nhìn chi tiết tinh tường"], "synonyms": ["sharp", "acute", "astute"], "antonyms": ["dull", "blunt", "indifferent"], "morphology": [{"part": "cene (kon-)", "kind": "root", "meaning": "sharp, wise, perceptive"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "sắc sảo, nhạy bén, tinh tường", "definitionEn": "very interested, eager, or enthusiastic; or having a sharp mind or edge"},
    "mythology": {"level": "B2", "pos": "noun", "phonetic": "/mɪˈθɒl.ə.dʒi/", "meaning": "a collection of traditional stories and myths belonging to a particular culture", "example": "I enjoy studying global mythology, as every culture embeds its core values within its legends.", "collocations": ["classical mythology - thần thoại cổ điển", "Norse mythology - thần thoại Bắc Âu"], "synonyms": ["folklore", "legend", "tradition"], "antonyms": ["history", "fact"], "morphology": [{"part": "myth (mythos)", "kind": "root", "meaning": "sacred story, legend"}, {"part": "-logy (logos)", "kind": "suffix", "meaning": "study, collection of"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "thần thoại học, thần thoại, hệ thống truyền thuyết thần thoại", "definitionEn": "a collection of traditional stories and myths belonging to a particular culture"},
    "microbiology": {"level": "C1", "pos": "noun", "phonetic": "/ˌmaɪ.kroʊ.baɪˈɑː.lə.dʒi/", "meaning": "the scientific study of microorganisms such as bacteria, viruses, and fungi", "example": "The microbiology laboratory conducts research on microscopic organisms.", "collocations": ["clinical microbiology - vi sinh vật học lâm sàng", "study microbiology - nghiên cứu vi sinh vật học"], "synonyms": ["bacteriology", "virology"], "antonyms": [], "morphology": [{"part": "micro-", "kind": "prefix", "meaning": "very small"}, {"part": "bio-", "kind": "root", "meaning": "life"}, {"part": "-logy", "kind": "suffix", "meaning": "study of"}], "source": "Cambridge EVP / Academic", "meaningVi": "ngành vi sinh vật học, ngành nghiên cứu về vi sinh vật", "definitionEn": "the scientific study of microorganisms such as bacteria, viruses, and fungi"},
    "physiology": {"level": "C1", "pos": "noun", "phonetic": "/ˌfɪz.iˈɒl.ə.dʒi/", "meaning": "the scientific study of how living organisms and their body parts function", "example": "I didn't fully grasp human physiology until I had the opportunity to attend the medical conference.", "collocations": ["human physiology - sinh lý học con người", "principles of physiology - các nguyên lý sinh lý học"], "synonyms": ["biological function", "anatomy"], "antonyms": [], "morphology": [{"part": "physio- (physis)", "kind": "prefix", "meaning": "nature, living organism"}, {"part": "-logy (logos)", "kind": "suffix", "meaning": "study of functions"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "ngành sinh lý học (nghiên cứu chức năng hoạt động của cơ thể sống)", "definitionEn": "the scientific study of how living organisms and their body parts function"},
    "radioactive": {"level": "B2", "pos": "adj", "phonetic": "/ˌreɪ.di.əʊˈæk.tɪv/", "meaning": "sending out harmful radiation caused when atomic nuclei break up", "example": "The explosion released highly radioactive fallout, leaving the area contaminated decades later.", "collocations": ["radioactive fallout - bụi phóng xạ", "radioactive waste - rác thải phóng xạ"], "synonyms": ["nuclear", "contaminated", "irradiated"], "antonyms": ["stable", "non-radioactive"], "morphology": [{"part": "radio- (radius)", "kind": "prefix", "meaning": "ray, radiation"}, {"part": "act (agere)", "kind": "root", "meaning": "drive, emit"}, {"part": "-ive", "kind": "suffix", "meaning": "tending to"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "có tính phóng xạ, phát ra tia phóng xạ độc hại", "definitionEn": "sending out harmful radiation caused when atomic nuclei break up"},
    "relativity": {"level": "C1", "pos": "noun", "phonetic": "/ˌrel.əˈtɪv.ə.ti/", "meaning": "the physics theory that space and time are relative to the observer's motion", "example": "Albert Einstein formulated the theory of relativity, which became a cornerstone of modern science.", "collocations": ["theory of relativity - thuyết tương đối", "general relativity - thuyết tương đối tổng quát"], "synonyms": ["interdependence", "spacetime physics"], "antonyms": ["absolutism"], "morphology": [{"part": "re-", "kind": "prefix", "meaning": "back"}, {"part": "lat (ferre)", "kind": "root", "meaning": "carry, relate"}, {"part": "-ivity", "kind": "suffix", "meaning": "state, principle"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "thuyết tương đối (vật lý học)", "definitionEn": "the physics theory that space and time are relative to the observer's motion"},
    "sociology": {"level": "B2", "pos": "noun", "phonetic": "/ˌsəʊ.siˈɒl.ə.dʒi/", "meaning": "the scientific study of human society, social relationships, and institutions", "example": "Although sociology is a social science, it plays a critical role in understanding human behavior.", "collocations": ["field of sociology - lĩnh vực xã hội học", "urban sociology - xã hội học đô thị"], "synonyms": ["social science", "demographics"], "antonyms": [], "morphology": [{"part": "socio- (socius)", "kind": "prefix", "meaning": "companion, society"}, {"part": "-logy (logos)", "kind": "suffix", "meaning": "science, study of"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "ngành xã hội học (nghiên cứu sự phát triển và hành vi xã hội)", "definitionEn": "the scientific study of human society, social relationships, and institutions"},
    "theoretical": {"level": "C1", "pos": "adj", "phonetic": "/ˌθɪəˈret.ɪ.kəl/", "meaning": "based on theories and ideas rather than practical experiments or experience", "example": "My entire proposal remains purely theoretical because I have not had the opportunity to put it into practice.", "collocations": ["purely theoretical - hoàn toàn mang tính lý thuyết", "theoretical framework - khung lý thuyết"], "synonyms": ["hypothetical", "conceptual", "abstract"], "antonyms": ["empirical", "practical", "applied"], "morphology": [{"part": "theor (theoria)", "kind": "root", "meaning": "contemplation, speculation"}, {"part": "-etical (-ical)", "kind": "suffix", "meaning": "pertaining to"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "thuộc về lý thuyết, dựa trên lý thuyết hơn là thực hành", "definitionEn": "based on theories and ideas rather than practical experiments or experience"},
    "administrator": {"level": "C1", "pos": "noun", "phonetic": "/ədˈmɪn.ɪ.streɪ.tər/", "meaning": "a person whose job is to manage and organize the affairs of a business or institution", "example": "The board hired a skilled administrator to oversee daily campus operations.", "collocations": ["system administrator - quản trị viên hệ thống", "hospital administrator - người quản lý bệnh viện"], "synonyms": ["executive", "manager", "director"], "antonyms": ["subordinate", "employee"], "morphology": [{"part": "ad-", "kind": "prefix", "meaning": "to, for"}, {"part": "ministr (minister)", "kind": "root", "meaning": "serve, manage"}, {"part": "-ator", "kind": "suffix", "meaning": "person who directs"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "Người quản lý, người điều hành hoặc quản trị viên kiểm soát một tổ chức, công ty hay cơ quan.", "definitionEn": "a person whose job is to manage and organize the affairs of a business or institution"},
    "affluent": {"level": "C1", "pos": "adj", "phonetic": "/ˈæf.lu.ənt/", "meaning": "having a great deal of money, wealth, and a high standard of living", "example": "They moved into an affluent neighborhood filled with private estates and luxury cars.", "collocations": ["affluent society - xã hội giàu có", "affluent lifestyle - lối sống thượng lưu"], "synonyms": ["wealthy", "prosperous", "opulent"], "antonyms": ["impoverished", "destitute", "poor"], "morphology": [{"part": "af- (ad-)", "kind": "prefix", "meaning": "to, toward"}, {"part": "flu (fluere)", "kind": "root", "meaning": "flow abundantly"}, {"part": "-ent", "kind": "suffix", "meaning": "being, characterized by"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "Giàu có, thịnh vượng, có nhiều tiền bạc và tài sản.", "definitionEn": "having a great deal of money, wealth, and a high standard of living"},
    "audit": {"level": "B2", "pos": "verb", "phonetic": "/ˈɔː.dɪt/", "meaning": "to conduct an official examination of financial accounts or organizational processes", "example": "The tax authority decided to audit the corporation's financial records.", "collocations": ["audit accounts - kiểm toán sổ sách tài khoản", "conduct an audit - thực hiện kiểm toán"], "synonyms": ["inspect", "examine", "scrutinize"], "antonyms": ["overlook", "ignore"], "morphology": [{"part": "aud (audire)", "kind": "root", "meaning": "hear, officially examine"}, {"part": "-it (-itus)", "kind": "suffix", "meaning": "official hearing/review"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "Kiểm toán, kiểm tra chính thức sổ sách và hồ sơ tài chính của cá nhân hay tổ chức.", "definitionEn": "to conduct an official examination of financial accounts or organizational processes"},
    "automate": {"level": "C1", "pos": "verb", "phonetic": "/ˈɔː.tə.meɪt/", "meaning": "to use machines or computers instead of human labor to do a job or process", "example": "The company plans to automate assembly operations to reduce labor costs.", "collocations": ["automate the process - tự động hóa quy trình", "fully automated - hoàn toàn tự động"], "synonyms": ["mechanize", "computerize", "streamline"], "antonyms": ["manualize"], "morphology": [{"part": "auto-", "kind": "prefix", "meaning": "self"}, {"part": "mat (men-)", "kind": "root", "meaning": "think, act on its own"}, {"part": "-ate", "kind": "suffix", "meaning": "make, cause to be"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "Tự động hóa, lắp đặt máy móc hoặc hệ thống máy tính để thực hiện công việc thay con người.", "definitionEn": "to use machines or computers instead of human labor to do a job or process"},
    "bribe": {"level": "C1", "pos": "verb", "phonetic": "/braɪb/", "meaning": "to dishonestly give money or gifts to someone to persuade them to help you", "example": "The suspect attempted to bribe the officer to avoid getting arrested.", "collocations": ["bribe an official - hối lộ quan chức", "accept a bribe - nhận tiền hối lộ"], "synonyms": ["corrupt", "buy off", "pay off"], "antonyms": [], "morphology": [{"part": "briber", "kind": "root", "meaning": "piece of bread, illicit inducement"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "Hối lộ, đút lót tiền hoặc lợi ích bất hợp pháp để thuyết phục ai đó giúp đỡ mình.", "definitionEn": "to dishonestly give money or gifts to someone to persuade them to help you"},
    "corrupt": {"level": "C1", "pos": "adj", "phonetic": "/kəˈrʌpt/", "meaning": "dishonest or illegal behavior, especially by people in positions of power", "example": "The government promised to punish corrupt officials who took public funds.", "collocations": ["corrupt official - quan chức tham nhũng", "corrupt practices - các hành vi tham nhũng"], "synonyms": ["dishonest", "venal", "unethical"], "antonyms": ["honest", "ethical", "incorruptible"], "morphology": [{"part": "cor- (com-)", "kind": "prefix", "meaning": "altogether, thoroughly"}, {"part": "rupt (rumpere)", "kind": "root", "meaning": "break, destroy integrity"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "Tham nhũng, tha hóa, vi phạm pháp luật hoặc đạo đức vì lợi ích tiền bạc, quyền lực.", "definitionEn": "dishonest or illegal behavior, especially by people in positions of power"},
    "dispose": {"level": "C1", "pos": "verb", "phonetic": "/dɪˈspoʊz/", "meaning": "to get rid of something that is no longer wanted or needed", "example": "Factories must safely dispose of hazardous chemical waste.", "collocations": ["dispose of waste - xử lý/vứt bỏ rác thải", "properly dispose - xử lý đúng quy cách"], "synonyms": ["discard", "get rid of", "jettison"], "antonyms": ["retain", "keep", "hoard"], "morphology": [{"part": "dis-", "kind": "prefix", "meaning": "apart, away"}, {"part": "pos (ponere)", "kind": "root", "meaning": "put, place, arrange"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "xử lý/vứt bỏ, Vứt bỏ, xử lý hoặc loại bỏ cái gì đó (thường đi kèm giới từ *of*).", "definitionEn": "to get rid of something that is no longer wanted or needed"},
    "headquarters": {"level": "B2", "pos": "noun", "phonetic": "/ˈhed.kwɔː.təz/", "meaning": "the main offices of an organization where its leaders and central management work", "example": "The tech giant moved its international headquarters to London to expand its European operations.", "collocations": ["corporate headquarters - trụ sở chính của tập đoàn", "set up headquarters - đặt trụ sở chính"], "synonyms": ["head office", "main office", "command center"], "antonyms": ["branch", "outpost"], "morphology": [{"part": "head", "kind": "prefix", "meaning": "chief, principal"}, {"part": "quarter (quartarius)", "kind": "root", "meaning": "district, residence, station"}, {"part": "-s", "kind": "suffix", "meaning": "collective noun"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "Trụ sở chính, đại bản doanh của một công ty, tổ chức hoặc lực lượng quân sự.", "definitionEn": "the main offices of an organization where its leaders and central management work"},
    "incentive": {"level": "C1", "pos": "noun", "phonetic": "/ɪnˈsen.tɪv/", "meaning": "something that encourages a person or organization to do something or work harder", "example": "The company offered a financial incentive to employees who met their quarterly sales targets.", "collocations": ["financial incentive - động lực tài chính", "provide an incentive - đưa ra động lực/sự khuyến khích"], "synonyms": ["inducement", "motivation", "stimulus"], "antonyms": ["deterrent", "disincentive"], "morphology": [{"part": "in-", "kind": "prefix", "meaning": "into, upon"}, {"part": "cent (canere)", "kind": "root", "meaning": "strike up a tune, spur"}, {"part": "-ive", "kind": "suffix", "meaning": "that which stimulates"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "sự khuyến khích, động lực, Động lực, sự khuyến khích hoặc phần thưởng nhằm thúc đẩy ai đó làm việc gì.", "definitionEn": "something that encourages a person or organization to do something or work harder"},
    "infrastructure": {"level": "B2", "pos": "noun", "phonetic": "/ˈɪn.frəˌstrʌk.tʃər/", "meaning": "the basic physical systems and structures a country or organization needs to function", "example": "The government invested billions of dollars to rebuild the country's aging infrastructure.", "collocations": ["transport infrastructure - cơ sở hạ tầng giao thông", "infrastructure development - sự phát triển cơ sở hạ tầng"], "synonyms": ["foundation", "framework", "public works"], "antonyms": ["superstructure"], "morphology": [{"part": "infra-", "kind": "prefix", "meaning": "below, underneath"}, {"part": "struct (struere)", "kind": "root", "meaning": "build, construct"}, {"part": "-ure", "kind": "suffix", "meaning": "system, result"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "Cơ sở hạ tầng (hệ thống giao thông, điện, nước, viễn thông...) cần thiết cho một quốc gia hoặc tổ chức hoạt động.", "definitionEn": "the basic physical systems and structures a country or organization needs to function"},
    "legislate": {"level": "C2", "pos": "verb", "phonetic": "/ˈledʒ.ɪ.sleɪt/", "meaning": "to make or enact laws officially through a parliament or government body", "example": "Parliament plans to legislate against illegal pollution by industrial factories.", "collocations": ["legislate against - làm luật cấm/chống lại", "power to legislate - quyền lập pháp"], "synonyms": ["enact laws", "codify", "decree"], "antonyms": ["repeal", "deregulate"], "morphology": [{"part": "legis (lex)", "kind": "root", "meaning": "law"}, {"part": "lat (ferre)", "kind": "root", "meaning": "propose, carry"}, {"part": "-ate", "kind": "suffix", "meaning": "enact, perform"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "lập pháp, làm luật, Lập pháp, ban hành luật pháp để điều chỉnh hoặc kiểm soát một hành vi hay lĩnh vực.", "definitionEn": "to make or enact laws officially through a parliament or government body"},
    "legitimate": {"level": "C1", "pos": "adj", "phonetic": "/lɪˈdʒɪt.ə.mət/", "meaning": "allowed by law, or reasonable, valid, and acceptable", "example": "They expressed legitimate concerns about the safety of the new medical treatment.", "collocations": ["legitimate business - doanh nghiệp hợp pháp", "legitimate concern - mối quan ngại chính đáng"], "synonyms": ["lawful", "valid", "justifiable"], "antonyms": ["illegitimate", "unlawful", "fraudulent"], "morphology": [{"part": "legitim (lex)", "kind": "root", "meaning": "lawful, rule-abiding"}, {"part": "-ate", "kind": "suffix", "meaning": "having status of"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "Hợp pháp, chính đáng, dựa trên lý do hoặc căn cứ hợp lý.", "definitionEn": "allowed by law, or reasonable, valid, and acceptable"},
    "manipulate": {"level": "C1", "pos": "verb", "phonetic": "/məˈnɪp.jə.leɪt/", "meaning": "to control or influence someone or something cleverly or unscrupulously", "example": "He tried to manipulate the media coverage to protect his reputation.", "collocations": ["manipulate public opinion - thao túng dư luận", "manipulate market prices - thao túng giá thị trường"], "synonyms": ["maneuver", "exploit", "influence"], "antonyms": ["leave alone", "respect"], "morphology": [{"part": "manipul (manus)", "kind": "root", "meaning": "hand, handful"}, {"part": "-ate", "kind": "suffix", "meaning": "handle, control"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "Thao túng, điều khiển hoặc ảnh hưởng một cách xảo quyệt/không công bằng tới người khác hoặc dữ liệu.", "definitionEn": "to control or influence someone or something cleverly or unscrupulously"},
    "merchandise": {"level": "C1", "pos": "noun", "phonetic": "/ˈmɜː.tʃən.daɪz/", "meaning": "goods that are bought, sold, or traded in commerce", "example": "The store displayed a wide variety of official sports merchandise near the entrance.", "collocations": ["official merchandise - hàng hóa chính hãng", "display merchandise - trưng bày hàng hóa"], "synonyms": ["goods", "wares", "commodities"], "antonyms": [], "morphology": [{"part": "merchand (merx)", "kind": "root", "meaning": "wares, commodities"}, {"part": "-ise", "kind": "suffix", "meaning": "goods, quality"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "Hàng hóa được bày bán hoặc chuẩn bị để mua bán.", "definitionEn": "goods that are bought, sold, or traded in commerce"},
    "retail": {"level": "B2", "pos": "noun", "phonetic": "/ˈriː.teɪl/", "meaning": "the sale of goods directly to the public in relatively small quantities for personal use", "example": "Online shopping has completely transformed the traditional retail industry.", "collocations": ["retail outlet / store - cửa hàng bán lẻ", "retail price - giá bán lẻ"], "synonyms": ["direct sales", "consumer trade"], "antonyms": ["wholesale"], "morphology": [{"part": "re-", "kind": "prefix", "meaning": "again"}, {"part": "tail (tailler)", "kind": "root", "meaning": "cut in pieces, sell individually"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "ngành bán lẻ, Việc bán lẻ (bán trực tiếp hàng hóa tới người tiêu dùng cuối cùng).", "definitionEn": "the sale of goods directly to the public in relatively small quantities for personal use"},
    "revenue": {"level": "B2", "pos": "noun", "phonetic": "/ˈrev.ən.juː/", "meaning": "the total income that a government or company receives regularly", "example": "The company's annual revenue increased by 15 percent thanks to successful marketing campaigns.", "collocations": ["generate revenue - tạo ra doanh thu", "annual revenue - doanh thu hàng năm"], "synonyms": ["income", "proceeds", "earnings"], "antonyms": ["expenditure", "expense", "outlay"], "morphology": [{"part": "re-", "kind": "prefix", "meaning": "back"}, {"part": "ven (venire)", "kind": "root", "meaning": "come, return"}, {"part": "-ue", "kind": "suffix", "meaning": "income, yield"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "Doanh thu, tổng số tiền một công ty hoặc chính phủ thu về.", "definitionEn": "the total income that a government or company receives regularly"},
    "rubbish": {"level": "B1", "pos": "noun", "phonetic": "/ˈrʌb.ɪʃ/", "meaning": "waste material or things that are no longer wanted and have been thrown away", "example": "Please remember to take out the rubbish before you leave the house.", "collocations": ["rubbish bin - thùng rác", "talk rubbish - nói nhảm nhí/vô lý"], "synonyms": ["garbage", "trash", "refuse"], "antonyms": ["treasure", "valuables"], "morphology": [{"part": "rubb (robous)", "kind": "root", "meaning": "rubble, waste fragments"}, {"part": "-ish", "kind": "suffix", "meaning": "collectivity"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "Rác thải, đồ bỏ đi; (nghĩa lóng) điều nhảm nhí/kém chất lượng.", "definitionEn": "waste material or things that are no longer wanted and have been thrown away"},
    "subsidy": {"level": "C1", "pos": "noun", "phonetic": "/ˈsʌb.sə.di/", "meaning": "money paid by a government or organization to reduce the cost of producing goods or services", "example": "The local government granted a state subsidy to support renewable energy projects.", "collocations": ["government subsidy - trợ cấp chính phủ", "agricultural subsidy - trợ cấp nông nghiệp"], "synonyms": ["grant", "financial aid", "allowance"], "antonyms": ["tax", "levy"], "morphology": [{"part": "sub-", "kind": "prefix", "meaning": "under, behind"}, {"part": "sid (sedere)", "kind": "root", "meaning": "sit in reserve, support"}, {"part": "-y (-ium)", "kind": "suffix", "meaning": "grant, assistance"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "tiền trợ cấp, trợ giá, Tiền trợ cấp, khoản tiền chính phủ chi trả để hỗ trợ doanh nghiệp hoặc ngành công nghiệp.", "definitionEn": "money paid by a government or organization to reduce the cost of producing goods or services"},
    "transaction": {"level": "B2", "pos": "noun", "phonetic": "/trænˈzæk.ʃən/", "meaning": "an occasion when someone buys or sells something, or an exchange of money", "example": "You will receive a confirmation email immediately after the financial transaction is completed.", "collocations": ["financial transaction - giao dịch tài chính", "online transaction - giao dịch trực tuyến"], "synonyms": ["deal", "exchange", "settlement"], "antonyms": [], "morphology": [{"part": "trans-", "kind": "prefix", "meaning": "across, through"}, {"part": "act (agere)", "kind": "root", "meaning": "drive, carry through"}, {"part": "-ion", "kind": "suffix", "meaning": "act, business deal"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "Giao dịch (hành vi mua bán, chuyển tiền hoặc trao đổi công việc).", "definitionEn": "an occasion when someone buys or sells something, or an exchange of money"},
    "violate": {"level": "C1", "pos": "verb", "phonetic": "/ˈvaɪ.ə.leɪt/", "meaning": "to break or act against a law, agreement, rule, or principle", "example": "Companies that violate safety regulations face heavy fines and potential closure.", "collocations": ["violate a law - vi phạm luật pháp", "violate human rights - vi phạm quyền con người"], "synonyms": ["breach", "infringe", "transgress"], "antonyms": ["obey", "comply", "uphold"], "morphology": [{"part": "viol (vis)", "kind": "root", "meaning": "force, breach, injure"}, {"part": "-ate", "kind": "suffix", "meaning": "commit, act upon"}], "source": "4000 Essential English Words Vol. 5", "meaningVi": "Vi phạm, xâm phạm (luật pháp, quy định, thỏa thuận, quyền riêng tư).", "definitionEn": "to break or act against a law, agreement, rule, or principle"}
};

var GERMAN_LEXICON = {
    // A1 - A2 Goethe-Zertifikat
    "wasser": { word: "Wasser", article: "das", plural: "¨-", level: "A1", pos: "noun", phonetic: "/ˈvasɐ/", meaning: "water; clear liquid essential for life", example: "Ein Glas Wasser, bitte.", synonyms: ["Trinkwasser", "Nass"], antonyms: [], morphology: [{"part": "Wasser (wat-)", "kind": "root", "meaning": "wet, flowing liquid"}], source: "Goethe-Zertifikat A1 / DWDS" },
    "buch": { word: "Buch", article: "das", plural: "Bücher", level: "A1", pos: "noun", phonetic: "/buːx/", meaning: "book", example: "Ich lese jeden Abend ein deutsches Buch.", synonyms: ["Band", "Werk"], antonyms: [], morphology: [{"part": "Buch (boks)", "kind": "root", "meaning": "beechwood tablet, book"}], source: "Goethe-Zertifikat A1 / DWDS" },
    "bahnhof": { word: "Bahnhof", article: "der", plural: "Bahnhöfe", level: "A1", pos: "noun", phonetic: "/ˈbaːnˌhoːf/", meaning: "train station, railway station", meaningVi: "nhà ga tàu hỏa", example: "Der Zug fährt pünktlich vom Bahnhof ab.", synonyms: ["Station", "Haltestelle"], antonyms: [], morphology: [{"part": "Bahn", "kind": "prefix", "meaning": "track, railway"}, {"part": "Hof", "kind": "root", "meaning": "courtyard, station"}], source: "Goethe-Zertifikat A1 / DWDS" },
    "lernen": { word: "lernen", article: "", plural: "", level: "A1", pos: "verb", phonetic: "/ˈlɛʁnən/", meaning: "to learn, to study", example: "Wir lernen jeden Tag zwanzig neue Wörter.", synonyms: ["studieren", "pauken"], antonyms: ["vergessen", "verlernen"], morphology: [{"part": "lern-", "kind": "root", "meaning": "follow a track, study"}, {"part": "-en", "kind": "suffix", "meaning": "verb infinitive"}], source: "Goethe-Zertifikat A1 / DWDS" },
    "verstehen": { word: "verstehen", article: "", plural: "", level: "A1", pos: "verb", phonetic: "/fɛɐ̯ˈʃteːən/", meaning: "to understand, to comprehend", example: "Kannst du diesen deutschen Satz verstehen?", synonyms: ["begreifen", "erfassen"], antonyms: ["missverstehen"], morphology: [{"part": "ver-", "kind": "prefix", "meaning": "thoroughly, before"}, {"part": "steh-", "kind": "root", "meaning": "stand, grasp"}, {"part": "-en", "kind": "suffix", "meaning": "verb infinitive"}], source: "Goethe-Zertifikat A1 / DWDS" },
    "erfahrung": { word: "Erfahrung", article: "die", plural: "-en", level: "A2", pos: "noun", phonetic: "/ɛɐ̯ˈfaːʁʊŋ/", meaning: "experience, practical knowledge", meaningVi: "kinh nghiệm, trải nghiệm", example: "Sie hat viel Erfahrung im Sprachenlernen.", synonyms: ["Praxis", "Routine"], antonyms: ["Unerfahrenheit"], morphology: [{"part": "er-", "kind": "prefix", "meaning": "attain by action"}, {"part": "fahr-", "kind": "root", "meaning": "travel, go through"}, {"part": "-ung", "kind": "suffix", "meaning": "noun of result"}], source: "Goethe-Zertifikat A2 / DWDS" },
    "sehenswürdigkeit": { word: "Sehenswürdigkeit", article: "die", plural: "-en", level: "A2", pos: "noun", phonetic: "/ˈzeːənsˌvʏʁdɪçkaɪ̯t/", meaning: "sight, landmark, tourist attraction", meaningVi: "danh lam thắng cảnh, địa điểm tham quan", example: "Das Brandlandburger Tor ist eine berühmte Sehenswürdigkeit.", synonyms: ["Attraktion", "Wahrzeichen"], antonyms: [], morphology: [{"part": "sehens-", "kind": "prefix", "meaning": "of seeing"}, {"part": "würdig", "kind": "root", "meaning": "worthy"}, {"part": "-keit", "kind": "suffix", "meaning": "quality, thing"}], source: "Goethe-Zertifikat A2 / DWDS" },
    "ziel": { word: "Ziel", article: "das", plural: "-e", level: "A2", pos: "noun", phonetic: "/t͡siːl/", meaning: "goal, target, destination", example: "Mein Ziel ist das Sprachniveau C1 in Deutsch.", synonyms: ["Zweck", "Absicht"], antonyms: ["Start", "Ausgangspunkt"], morphology: [{"part": "Ziel (til-)", "kind": "root", "meaning": "fixed point, target, goal"}], source: "Goethe-Zertifikat A2 / DWDS" },

    // B1 - B2 Goethe-Zertifikat / Telc / DWDS
    "zeitraum": { word: "Zeitraum", article: "der", plural: "Zeiträume", level: "B1", pos: "noun", phonetic: "/ˈt͡saɪ̯tˌʁaʊ̯m/", meaning: "period of time, time span, interval", meaningVi: "khoảng thời gian, giai đoạn", example: "Über einen längeren Zeitraum bleibt das Wissen im Gedächtnis.", synonyms: ["Zeitspanne", "Periode"], antonyms: ["Augenblick", "Moment"], morphology: [{"part": "Zeit", "kind": "prefix", "meaning": "time"}, {"part": "Raum", "kind": "root", "meaning": "space, span"}], source: "Goethe-Zertifikat B1 / DWDS" },
    "zusammenhang": { word: "Zusammenhang", article: "der", plural: "Zusammenhänge", level: "B1", pos: "noun", phonetic: "/t͡suˈzamənhaŋ/", meaning: "context, connection, relationship", meaningVi: "mối liên hệ, ngữ cảnh, bối cảnh", example: "Man sollte neue Vokabeln immer im Zusammenhang lernen.", synonyms: ["Kontext", "Verbindung"], antonyms: ["Trennung"], morphology: [{"part": "zusammen-", "kind": "prefix", "meaning": "together"}, {"part": "Hang (hängen)", "kind": "root", "meaning": "hang, connection"}], source: "Goethe-Zertifikat B1 / DWDS" },
    "entscheiden": { word: "entscheiden", article: "", plural: "", level: "B1", pos: "verb", phonetic: "/ɛntˈʃaɪ̯dn̩/", meaning: "to decide, to determine", example: "Der Algorithmus entscheidet, wann eine Karte wiederholt wird.", synonyms: ["beschließen", "festlegen"], antonyms: ["zögern", "schwanken"], morphology: [{"part": "ent-", "kind": "prefix", "meaning": "apart, out of"}, {"part": "scheid-", "kind": "root", "meaning": "separate, determine"}, {"part": "-en", "kind": "suffix", "meaning": "verb infinitive"}], source: "Goethe-Zertifikat B1 / DWDS" },
    "herausforderung": { word: "Herausforderung", article: "die", plural: "-en", level: "B1", pos: "noun", phonetic: "/hɛˈʁaʊ̯sˌfɔʁdəʁʊŋ/", meaning: "challenge, demanding task", meaningVi: "thử thách, thách thức", example: "Deutsche Artikel und Pluralformen sind eine spannende Herausforderung.", synonyms: ["Aufgabe", "Erprobung"], antonyms: ["Routine", "Kinderspiel"], morphology: [{"part": "heraus-", "kind": "prefix", "meaning": "out toward speaker"}, {"part": "forder-", "kind": "root", "meaning": "demand, summon"}, {"part": "-ung", "kind": "suffix", "meaning": "noun of action"}], source: "Goethe-Zertifikat B1 / DWDS" },
    "nachhaltig": { word: "nachhaltig", article: "", plural: "", level: "B2", pos: "adj", phonetic: "/ˈnaːxˌhaltɪç/", meaning: "sustainable, lasting, enduring", meaningVi: "bền vững, lâu dài", example: "Spaced Repetition sorgt für einen nachhaltigen Lernerfolg.", synonyms: ["dauerhaft", "langfristig"], antonyms: ["kurzlebig", "vergänglich"], morphology: [{"part": "nach-", "kind": "prefix", "meaning": "after, continuing"}, {"part": "halt-", "kind": "root", "meaning": "hold, last"}, {"part": "-ig", "kind": "suffix", "meaning": "characterized by"}], source: "DWDS / Telc B2" },
    "nachhaltigkeit": { word: "Nachhaltigkeit", article: "die", plural: "-", level: "B2", pos: "noun", phonetic: "/ˈnaːxˌhaltɪçkaɪ̯t/", meaning: "sustainability, long-term durability", meaningVi: "tính bền vững", example: "Nachhaltigkeit beim Lernen bedeutet regelmäßige Wiederholung.", synonyms: ["Beständigkeit"], antonyms: ["Kurzlebigkeit"], morphology: [{"part": "nach-", "kind": "prefix", "meaning": "after, continuing"}, {"part": "haltig", "kind": "root", "meaning": "lasting, enduring"}, {"part": "-keit", "kind": "suffix", "meaning": "state, quality"}], source: "DWDS / Telc B2" },
    "bewusstsein": { word: "Bewusstsein", article: "das", plural: "-", level: "B2", pos: "noun", phonetic: "/bəˈvʊstzaɪ̯n/", meaning: "consciousness, awareness", example: "Das sprachliche Bewusstsein wächst mit jedem gelesenen Text.", synonyms: ["Gewahrsein"], antonyms: ["Unbewusstheit"], morphology: [{"part": "be-", "kind": "prefix", "meaning": "equipped with"}, {"part": "wusst (wissen)", "kind": "root", "meaning": "known, aware"}, {"part": "-sein", "kind": "suffix", "meaning": "state of being"}], source: "DWDS / Goethe B2" },
    "erkenntnis": { word: "Erkenntnis", article: "die", plural: "-se", level: "B2", pos: "noun", phonetic: "/ɛɐ̯ˈkɛntnɪs/", meaning: "insight, realization, finding", meaningVi: "nhận thức, sự phát hiện, tri thức rút ra", example: "Das ist eine wichtige wissenschaftliche Erkenntnis.", synonyms: ["Einsicht", "Befund"], antonyms: ["Irrtum", "Unwissenheit"], morphology: [{"part": "er-", "kind": "prefix", "meaning": "come to, achieve"}, {"part": "kennt (kennen)", "kind": "root", "meaning": "know, discern"}, {"part": "-nis", "kind": "suffix", "meaning": "result, insight"}], source: "DWDS / Goethe B2" },
    "voraussetzung": { word: "Voraussetzung", article: "die", plural: "-en", level: "B2", pos: "noun", phonetic: "/foˈʁaʊ̯sˌzɛt͡sʊŋ/", meaning: "prerequisite, precondition, requirement", meaningVi: "điều kiện tiên quyết, tiền đề", example: "Aufmerksamkeit ist die wichtigste Voraussetzung für das Gedächtnis.", synonyms: ["Bedingung", "Grundlage"], antonyms: ["Folge", "Ergebnis"], morphology: [{"part": "voraus-", "kind": "prefix", "meaning": "in advance, ahead"}, {"part": "setz-", "kind": "root", "meaning": "place, establish"}, {"part": "-ung", "kind": "suffix", "meaning": "condition, noun"}], source: "DWDS / Goethe B2" },
    "überblick": { word: "Überblick", article: "der", plural: "-e", level: "B2", pos: "noun", phonetic: "/ˈyːbɐˌblɪk/", meaning: "overview, survey, summary", example: "Das Dashboard gibt einen klaren Überblick über alle fälligen Karten.", synonyms: ["Übersicht"], antonyms: ["Detailansicht"], morphology: [{"part": "über-", "kind": "prefix", "meaning": "over, across"}, {"part": "Blick", "kind": "root", "meaning": "gaze, view"}], source: "DWDS / Goethe B2" },

    // C1 - C2 Advanced & Academic German (DWDS / DSH / TestDaF)
    "gewährleisten": { word: "gewährleisten", article: "", plural: "", level: "C1", pos: "verb", phonetic: "/ɡəˈvɛːɐ̯ˌlaɪ̯stn̩/", meaning: "to guarantee, to ensure, to warrant", meaningVi: "đảm bảo, bảo đảm", example: "Regelmäßige Intervalle gewährleisten eine hohe Behaltensquote.", synonyms: ["sicherstellen", "garantieren"], antonyms: ["gefährden", "verhindern"], morphology: [{"part": "Gewähr", "kind": "prefix", "meaning": "warranty, surety"}, {"part": "leist-", "kind": "root", "meaning": "perform, fulfill"}, {"part": "-en", "kind": "suffix", "meaning": "verb infinitive"}], source: "DWDS / TestDaF C1" },
    "auseinandersetzen": { word: "auseinandersetzen", article: "sich", plural: "", level: "C1", pos: "verb", phonetic: "/aʊ̯sʔaɪ̯ˈnandɐˌzɛt͡sn̩/", meaning: "to grapple with, to examine critically, to engage deeply with", meaningVi: "nghiên cứu kỹ, đối mặt và giải quyết vấn đề", example: "Wer sich intensiv mit einem Thema auseinandersetzt, versteht es tiefer.", synonyms: ["beschäftigen", "analysieren"], antonyms: ["ignorieren", "meiden"], morphology: [{"part": "auseinander-", "kind": "prefix", "meaning": "apart from one another"}, {"part": "setz-", "kind": "root", "meaning": "place, examine"}, {"part": "-en", "kind": "suffix", "meaning": "verb infinitive"}], source: "DWDS / TestDaF C1" },
    "widerspiegeln": { word: "widerspiegeln", article: "", plural: "", level: "C1", pos: "verb", phonetic: "/ˈviːdɐˌʃpiːɡl̩n/", meaning: "to reflect, to mirror", meaningVi: "phản ánh, thể hiện", example: "Die Statistiken spiegeln deinen täglichen Lernfortschritt genau wider.", synonyms: ["reflektieren", "abbilden"], antonyms: ["verzerren"], morphology: [{"part": "wider-", "kind": "prefix", "meaning": "back, against"}, {"part": "spiegel-", "kind": "root", "meaning": "mirror, reflect"}, {"part": "-n", "kind": "suffix", "meaning": "verb infinitive"}], source: "DWDS / TestDaF C1" },
    "beeinträchtigen": { word: "beeinträchtigen", article: "", plural: "", level: "C1", pos: "verb", phonetic: "/bəˈʔaɪ̯ntʁɛçtɪɡn̩/", meaning: "to impair, to affect negatively, to compromise", meaningVi: "làm ảnh hưởng xấu, làm suy giảm, gây tổn hại", example: "Schlafmangel kann die Konsolidierung im Gedächtnis stark beeinträchtigen.", synonyms: ["schaden", "mindern"], antonyms: ["fördern", "stärken"], morphology: [{"part": "be-", "kind": "prefix", "meaning": "cause to have"}, {"part": "einträchtig (Eintrag)", "kind": "root", "meaning": "encroachment, detriment"}, {"part": "-en", "kind": "suffix", "meaning": "verb infinitive"}], source: "DWDS / DSH C1" },
    "gegebenheit": { word: "Gegebenheit", article: "die", plural: "-en", level: "C1", pos: "noun", phonetic: "/ɡəˈɡeːbn̩haɪ̯t/", meaning: "circumstance, given condition, reality", meaningVi: "điều kiện thực tế, hoàn cảnh hiện có", example: "Man muss sich an die örtlichen Gegebenheiten anpassen.", synonyms: ["Umstand", "Verhältnis"], antonyms: ["Hypothese"], morphology: [{"part": "ge-", "kind": "prefix", "meaning": "past participle"}, {"part": "geben", "kind": "root", "meaning": "given, existing"}, {"part": "-heit", "kind": "suffix", "meaning": "condition, reality"}], source: "DWDS / TestDaF C1" },
    "wahrscheinlichkeit": { word: "Wahrscheinlichkeit", article: "die", plural: "-en", level: "C1", pos: "noun", phonetic: "/vaːɐ̯ˈʃaɪ̯nlɪçkaɪ̯t/", meaning: "probability, likelihood", example: "Das Intervall richtet sich nach der Wahrscheinlichkeit des Vergessens.", synonyms: ["Chance", "Möglichkeit"], antonyms: ["Unmöglichkeit", "Gewissheit"], morphology: [{"part": "wahr-", "kind": "prefix", "meaning": "true"}, {"part": "schein-", "kind": "root", "meaning": "appear, seem"}, {"part": "-lichkeit", "kind": "suffix", "meaning": "quality of being likely"}], source: "DWDS / DSH C1" },
    "unabdingbar": { word: "unabdingbar", article: "", plural: "", level: "C2", pos: "adj", phonetic: "/ˌʊnʔapˈdɪŋbaːɐ̯/", meaning: "indispensable, essential, sine qua non", meaningVi: "không thể thiếu, bắt buộc, thiết yếu", example: "Aktives Abrufen ist für den langfristigen Wissenserwerb unabdingbar.", synonyms: ["unerlässlich", "notwendig"], antonyms: ["entbehrlich", "überflüssig"], morphology: [{"part": "un-", "kind": "prefix", "meaning": "not"}, {"part": "ab-", "kind": "prefix", "meaning": "away"}, {"part": "ding-", "kind": "root", "meaning": "negotiate, waive"}, {"part": "-bar", "kind": "suffix", "meaning": "able to be"}], source: "DWDS C2" },
    "befindlichkeit": { word: "Befindlichkeit", article: "die", plural: "-en", level: "C2", pos: "noun", phonetic: "/bəˈfɪntlɪçkaɪ̯t/", meaning: "mental state, sensibility, mood", example: "Der Roman beschreibt die gesellschaftliche Befindlichkeit einer Epoche.", synonyms: ["Gemütslage"], antonyms: [], morphology: [{"part": "be-", "kind": "prefix", "meaning": "state"}, {"part": "find-", "kind": "root", "meaning": "find, feel oneself"}, {"part": "-lichkeit", "kind": "suffix", "meaning": "sensibility, state"}], source: "DWDS C2" },
    "fingerspitzengefühl": { word: "Fingerspitzengefühl", article: "das", plural: "-", level: "C2", pos: "noun", phonetic: "/ˈfɪŋɐʃpɪt͡sn̩ɡəˌfyːl/", meaning: "tact, intuitive flair, delicate sensitivity", example: "Die Übersetzung literarischer Texte erfordert sprachliches Fingerspitzengefühl.", synonyms: ["Feingefühl", "Taktgefühl"], antonyms: ["Taktlosigkeit", "Plumpheit"], morphology: [{"part": "Finger", "kind": "prefix", "meaning": "finger"}, {"part": "Spitzen", "kind": "root", "meaning": "tips"}, {"part": "Gefühl", "kind": "suffix", "meaning": "feeling, intuitive tact"}], source: "DWDS C2" },
    "weitsicht": { word: "Weitsicht", article: "die", plural: "-", level: "C2", pos: "noun", phonetic: "/ˈvaɪ̯tˌzɪçt/", meaning: "foresight, farsightedness, prudence", example: "Mit strategischer Weitsicht plant er sein tägliches Lernpensum.", synonyms: ["Voraussicht", "Weitblick"], antonyms: ["Kurzsichtigkeit"], morphology: [{"part": "weit-", "kind": "prefix", "meaning": "far, wide"}, {"part": "Sicht (sehen)", "kind": "root", "meaning": "sight, vision"}], source: "DWDS C2" }
};

var HIGH_FREQ_EN_A1 = [
    "time", "year", "people", "way", "day", "man", "thing", "woman", "life", "child",
    "world", "school", "state", "family", "student", "group", "country", "problem",
    "hand", "part", "place", "case", "week", "company", "system", "program", "question",
    "work", "government", "number", "night", "point", "home", "water", "room", "mother",
    "area", "money", "story", "fact", "month", "lot", "right", "study", "book", "eye",
    "job", "word", "business", "issue", "side", "kind", "head", "house", "service",
    "friend", "father", "power", "hour", "game", "line", "end", "member", "law", "car",
    "city", "community", "name", "president", "team", "minute", "idea", "kid", "body",
    "information", "back", "parent", "face", "others", "level", "office", "door",
    "health", "person", "art", "war", "history", "party", "result", "change", "morning",
    "reason", "research", "girl", "guy", "moment", "air", "teacher", "force", "education"
];

var HIGH_FREQ_DE_A1_A2 = [
    "tag", "jahr", "zeit", "mensch", "mann", "frau", "kind", "welt", "schule", "arbeit",
    "haus", "stadt", "land", "frage", "antwort", "wort", "satz", "sprache", "freund",
    "familie", "geld", "auto", "weg", "hand", "auge", "kopf", "abend", "morgen", "nacht",
    "woche", "monat", "stunde", "minute", "name", "platz", "zimmer", "tür", "fenster",
    "tisch", "stuhl", "essen", "trinken", "gehen", "kommen", "machen", "sagen", "geben",
    "nehmen", "finden", "bleiben", "stehen", "sehen", "hören", "sprechen", "lesen",
    "schreiben", "arbeiten", "spielen", "kaufen", "helfen", "wohnen", "leben", "wissen",
    "kennen", "denken", "glauben", "hoffen", "wünschen", "brauchen", "zeigen", "führen"
];

function parseGermanHeadword(rawTerm) {
    var cleaned = String(rawTerm || "").trim();
    var article = "";
    var plural = "";
    var preposition = "";
    var coreWord = cleaned;

    // Extract bracketed or comma-separated plural e.g. "der Zeitraum (-e)" or "der Zeitraum, ¨-e"
    var parenMatch = coreWord.match(/\(([^)]+)\)\s*$/);
    if (parenMatch) {
        var inside = parenMatch[1].trim();
        if (/^(?:pl\.?\s*)?[-¨a-zA-ZäöüÄÖÜß/]+$/.test(inside) && !/^(?:noun|verb|adj|adv|n|v|m|f|nt)$/i.test(inside)) {
            plural = inside.replace(/^pl\.?\s*/i, "");
            coreWord = coreWord.slice(0, parenMatch.index).trim();
        }
    }
    var commaPlural = coreWord.match(/^(.+?),\s*([-¨][^\s,]*|[A-ZÄÖÜ][a-zäöüß]+)$/);
    if (commaPlural && !/^(der|die|das)$/i.test(commaPlural[2])) {
        coreWord = commaPlural[1].trim();
        if (!plural) plural = commaPlural[2].trim();
    }

    // Match leading "der/die/das/sich "
    var leadingArticle = coreWord.match(/^(der|die|das|sich)\s+(.+)$/i);
    if (leadingArticle) {
        article = leadingArticle[1].toLowerCase();
        coreWord = leadingArticle[2].trim();
    } else {
        // Match trailing ", der/die/das"
        var trailingArticle = coreWord.match(/^(.+?),\s*(der|die|das)$/i);
        if (trailingArticle) {
            coreWord = trailingArticle[1].trim();
            article = trailingArticle[2].toLowerCase();
        }
    }

    // Match trailing governed preposition e.g. "auseinandersetzen mit", "teilnehmen an", "abhängen von"
    var trailingPrep = coreWord.match(/^([a-zA-ZäöüÄÖÜß]{4,})\s+(mit|an|auf|über|für|von|zu|in|um|nach|vor|aus|bei|gegen|durch|unter|zwischen)$/i);
    if (trailingPrep) {
        coreWord = trailingPrep[1].trim();
        preposition = trailingPrep[2].toLowerCase();
    }

    return {
        word: coreWord,
        article: article,
        plural: plural,
        preposition: preposition
    };
}

function inferGermanArticle(word) {
    var w = String(word || "").trim();
    if (!w || w.indexOf(" ") >= 0) return "";
    var lower = w.toLowerCase();
    if (GERMAN_LEXICON[lower]) {
        if (GERMAN_LEXICON[lower].article) return GERMAN_LEXICON[lower].article;
        if (GERMAN_LEXICON[lower].pos && GERMAN_LEXICON[lower].pos !== "noun") return "";
    }
    // Only infer noun article when capitalized like a German noun
    var isCapitalized = /^[A-ZÄÖÜ]/.test(w);
    if (!isCapitalized) return "";
    if (/(?:ung|heit|keit|schaft|tät|ion|ik|enz|anz|erei|ie|ur)$/.test(lower)) return "die";
    if (/(?:chen|lein|ment|tum|um|ma)$/.test(lower)) return "das";
    if (/(?:ismus|ling|or|ant|ent|ist)$/.test(lower)) return "der";
    if (/^ge[a-zäöüß]+e$/.test(lower)) return "das";
    return "";
}

function detectLanguage(rawTerm, explicitLanguage) {
    var exp = String(explicitLanguage || "").trim().toLowerCase();
    if (exp === "other" || exp === "general") {
        return exp;
    }
    var text = String(rawTerm || "").trim();
    if (!text) return (exp === "de" ? "de" : "en");
    if (/^(?:der|die|das|sich)\s+[A-Za-zÄÖÜäöüß]/i.test(text)) return "de";
    if (/[äöüÄÖÜß]/.test(text)) return "de";
    var parsed = parseGermanHeadword(text);
    var lower = parsed.word.toLowerCase();
    if (GERMAN_LEXICON[lower] && !ENGLISH_LEXICON[lower]) return "de";
    if (ENGLISH_LEXICON[lower] && !GERMAN_LEXICON[lower]) return "en";
    if (exp === "de" || exp === "en") {
        return exp;
    }
    if (HIGH_FREQ_DE_A1_A2.indexOf(lower) >= 0) return "de";
    if (/^[A-ZÄÖÜ][a-zäöüß]+(?:ung|keit|heit|schaft|tät|chen|lein)$/.test(parsed.word)) return "de";
    return "en";
}

function stemEnglish(word) {
    var w = String(word || "").toLowerCase().trim();
    var candidates = [w];
    if (w.endsWith("ies") && w.length > 4) candidates.push(w.slice(0, -3) + "y");
    if (w.endsWith("ied") && w.length > 4) candidates.push(w.slice(0, -3) + "y");
    if (w.endsWith("es") && w.length > 4) {
        candidates.push(w.slice(0, -2));
        candidates.push(w.slice(0, -1));
    }
    if (w.endsWith("s") && w.length > 3) candidates.push(w.slice(0, -1));
    if (w.endsWith("ing") && w.length > 5) {
        var baseIng = w.slice(0, -3);
        candidates.push(baseIng);
        candidates.push(baseIng + "e");
        if (baseIng.length > 2 && baseIng[baseIng.length - 1] === baseIng[baseIng.length - 2]) {
            candidates.push(baseIng.slice(0, -1));
        }
    }
    if (w.endsWith("ed") && w.length > 4) {
        var baseEd = w.slice(0, -2);
        candidates.push(baseEd);
        candidates.push(baseEd + "e");
        if (baseEd.length > 2 && baseEd[baseEd.length - 1] === baseEd[baseEd.length - 2]) {
            candidates.push(baseEd.slice(0, -1));
        }
    }
    if (w.endsWith("ly") && w.length > 4) candidates.push(w.slice(0, -2));
    if (w.endsWith("ness") && w.length > 6) candidates.push(w.slice(0, -4));
    if (w.endsWith("ment") && w.length > 6) candidates.push(w.slice(0, -4));
    return candidates;
}

function stemGerman(word) {
    var w = String(word || "").toLowerCase().trim();
    var candidates = [w];
    if (w.endsWith("en") && w.length > 4) candidates.push(w.slice(0, -2));
    if (w.endsWith("n") && w.length > 4) candidates.push(w.slice(0, -1));
    if (w.endsWith("e") && w.length > 4) candidates.push(w.slice(0, -1));
    if (w.endsWith("er") && w.length > 4) candidates.push(w.slice(0, -2));
    if (w.endsWith("es") && w.length > 4) candidates.push(w.slice(0, -2));
    if (w.endsWith("em") && w.length > 4) candidates.push(w.slice(0, -2));
    if (w.endsWith("st") && w.length > 4) candidates.push(w.slice(0, -2) + "en");
    if (w.endsWith("t") && w.length > 4) candidates.push(w.slice(0, -1) + "en");
    if (w.startsWith("ge") && w.endsWith("t") && w.length > 5) {
        candidates.push(w.slice(2, -1) + "en");
    }
    return candidates;
}

function estimateCefrHeuristic(word, language) {
    var w = String(word || "").trim().toLowerCase();
    if (!w) return { level: "B1", source: "Heuristic Estimate", confidence: "low" };

    if (language === "de") {
        if (HIGH_FREQ_DE_A1_A2.indexOf(w) >= 0) {
            return { level: w.length <= 5 ? "A1" : "A2", source: "Goethe Core Frequency", confidence: "high" };
        }
        if (/^(?:auseinander|zusammen|widerspiegeln|gewähr|beeinträch|unabding|veranschau|berücksichtig)/.test(w)
                || /(?:fähigkeit|würdigkeit|mäßigkeit|bewusstsein|wahrscheinlichkeit)$/.test(w)
                || w.length >= 15) {
            return { level: w.length >= 17 ? "C2" : "C1", source: "DWDS Morphological Profile", confidence: "medium" };
        }
        if (/(?:ung|keit|heit|schaft|tät|setzung|forderung|nahme|hältnis)$/.test(w) || w.length >= 10) {
            return { level: w.length >= 12 ? "B2" : "B1", source: "DWDS Morphological Profile", confidence: "medium" };
        }
        if (w.length <= 5) {
            return { level: "A1", source: "DWDS Morphological Profile", confidence: "medium" };
        }
        if (w.length <= 7) {
            return { level: "A2", source: "DWDS Morphological Profile", confidence: "medium" };
        }
        return { level: "B1", source: "DWDS Morphological Profile", confidence: "medium" };
    }

    // English heuristics
    if (HIGH_FREQ_EN_A1.indexOf(w) >= 0) {
        return { level: "A1", source: "Oxford 3000 Core", confidence: "high" };
    }
    if (/(?:ubiquit|ephemer|quintessent|corrobor|obfusc|serendip|idiosyncra|paradigm|juxtapos|amelior|acerb|magnanim|perspicac)/.test(w)
            || /(?:aneous|itious|ological|isability|ification)$/.test(w)
            || w.length >= 14) {
        return { level: w.length >= 14 ? "C2" : "C1", source: "Academic / EVP Profile", confidence: "medium" };
    }
    if (/^(?:circum|contra|inter|trans|retro|pseudo|omni|macro|micro|multi|hyper)/.test(w)
            || /(?:bility|tious|cious|scent|mentary|tory)$/.test(w)
            || w.length >= 11) {
        return { level: "C1", source: "Academic / EVP Profile", confidence: "medium" };
    }
    if (/(?:tion|sion|ment|ence|ance|ive|ous|able|ible|ize|ise)$/.test(w) || w.length >= 8) {
        return { level: w.length >= 10 ? "B2" : "B1", source: "EVP Morphological Profile", confidence: "medium" };
    }
    if (w.length <= 4) {
        return { level: "A1", source: "EVP Morphological Profile", confidence: "medium" };
    }
    if (w.length <= 6) {
        return { level: "A2", source: "EVP Morphological Profile", confidence: "medium" };
    }
    return { level: "B1", source: "EVP Morphological Profile", confidence: "medium" };
}

function inferPartOfSpeech(word, language, article) {
    var w = String(word || "").trim();
    var lower = w.toLowerCase();
    if (!w) return "";
    if (language === "de") {
        if (article === "der" || article === "die" || article === "das" || /^[A-ZÄÖÜ]/.test(w)) return "noun";
        if (/(?:lich|ig|isch|bar|sam|los|haft|voll)$/.test(lower)) return "adj";
        if (/(?:en|ern|eln|ieren)$/.test(lower)) return "verb";
        return "word";
    }
    if (/(?:ly)$/.test(lower) && lower.length > 4) return "adv";
    if (/(?:ous|ful|less|able|ible|ive|ic|al|ant|ent)$/.test(lower)) return "adj";
    if (/(?:tion|sion|ment|ness|ity|ance|ence|ship|hood|ism)$/.test(lower)) return "noun";
    if (/(?:ize|ise|ify|ate|en)$/.test(lower)) return "verb";
    return "word";
}

function formatMorphology(cardOrMorphology) {
    if (!cardOrMorphology) return "";
    if (typeof cardOrMorphology === "string") return cardOrMorphology.trim();
    var list = Array.isArray(cardOrMorphology)
        ? cardOrMorphology
        : (Array.isArray(cardOrMorphology.morphology) ? cardOrMorphology.morphology : []);
    if (!list || list.length === 0) {
        return typeof cardOrMorphology.morphologyText === "string" ? cardOrMorphology.morphologyText.trim() : "";
    }
    var parts = [];
    for (var i = 0; i < list.length; i++) {
        var item = list[i];
        if (!item) continue;
        if (typeof item === "string") {
            if (item.trim()) parts.push(item.trim());
            continue;
        }
        var p = String(item.part || "").trim();
        var m = String(item.meaning || "").trim();
        if (!p) continue;
        parts.push(m ? (p + " (" + m + ")") : p);
    }
    return parts.join(" + ");
}

var EN_PREFIX_RULES = [
    { prefix: "contra", label: "contra-", meaning: "against, opposite" },
    { prefix: "circum", label: "circum-", meaning: "around" },
    { prefix: "inter", label: "inter-", meaning: "between, among" },
    { prefix: "intra", label: "intra-", meaning: "within" },
    { prefix: "trans", label: "trans-", meaning: "across, beyond" },
    { prefix: "super", label: "super-", meaning: "above, beyond" },
    { prefix: "infra", label: "infra-", meaning: "below, beneath" },
    { prefix: "under", label: "under-", meaning: "beneath, insufficient" },
    { prefix: "over", label: "over-", meaning: "excessive, above" },
    { prefix: "anti", label: "anti-", meaning: "against" },
    { prefix: "auto", label: "auto-", meaning: "self" },
    { prefix: "fore", label: "fore-", meaning: "before, in front" },
    { prefix: "post", label: "post-", meaning: "after" },
    { prefix: "pre", label: "pre-", meaning: "before" },
    { prefix: "pro", label: "pro-", meaning: "forward, for" },
    { prefix: "sub", label: "sub-", meaning: "under, below" },
    { prefix: "syn", label: "syn-", meaning: "together" },
    { prefix: "sym", label: "sym-", meaning: "together" },
    { prefix: "com", label: "com-", meaning: "together, with" },
    { prefix: "con", label: "con-", meaning: "together, with" },
    { prefix: "col", label: "col-", meaning: "together" },
    { prefix: "cor", label: "cor-", meaning: "altogether" },
    { prefix: "dis", label: "dis-", meaning: "apart, not" },
    { prefix: "mis", label: "mis-", meaning: "wrongly" },
    { prefix: "non", label: "non-", meaning: "not" },
    { prefix: "out", label: "out-", meaning: "beyond, surpassing" },
    { prefix: "per", label: "per-", meaning: "through, thoroughly" },
    { prefix: "ab", label: "ab-", meaning: "away, from" },
    { prefix: "ad", label: "ad-", meaning: "to, toward" },
    { prefix: "de", label: "de-", meaning: "down, away, completely" },
    { prefix: "ex", label: "ex-", meaning: "out, forth" },
    { prefix: "in", label: "in-", meaning: "in, into / not" },
    { prefix: "im", label: "im-", meaning: "into / not" },
    { prefix: "ir", label: "ir-", meaning: "not" },
    { prefix: "il", label: "il-", meaning: "not" },
    { prefix: "ob", label: "ob-", meaning: "against, toward" },
    { prefix: "re", label: "re-", meaning: "again, back" },
    { prefix: "un", label: "un-", meaning: "not, reverse" },
    { prefix: "en", label: "en-", meaning: "put into, cause" },
    { prefix: "em", label: "em-", meaning: "put into" }
];

var EN_SUFFIX_RULES = [
    { suffix: "ification", label: "-ification", meaning: "act of making" },
    { suffix: "ability", label: "-ability", meaning: "capacity to be" },
    { suffix: "ibility", label: "-ibility", meaning: "capacity to be" },
    { suffix: "ology", label: "-logy", meaning: "study, science of" },
    { suffix: "ation", label: "-ation", meaning: "action, process" },
    { suffix: "ition", label: "-ition", meaning: "state, action" },
    { suffix: "tious", label: "-tious", meaning: "characterized by" },
    { suffix: "cious", label: "-cious", meaning: "full of" },
    { suffix: "ment", label: "-ment", meaning: "result, action" },
    { suffix: "ness", label: "-ness", meaning: "state, quality" },
    { suffix: "ship", label: "-ship", meaning: "status, condition" },
    { suffix: "hood", label: "-hood", meaning: "condition, group" },
    { suffix: "less", label: "-less", meaning: "without" },
    { suffix: "able", label: "-able", meaning: "able to be" },
    { suffix: "ible", label: "-ible", meaning: "able to be" },
    { suffix: "ance", label: "-ance", meaning: "state, quality" },
    { suffix: "ence", label: "-ence", meaning: "state, quality" },
    { suffix: "tion", label: "-tion", meaning: "act, process" },
    { suffix: "sion", label: "-sion", meaning: "act, state" },
    { suffix: "ator", label: "-ator", meaning: "agent, doer" },
    { suffix: "ture", label: "-ture", meaning: "result, system" },
    { suffix: "ical", label: "-ical", meaning: "pertaining to" },
    { suffix: "ful", label: "-ful", meaning: "full of" },
    { suffix: "ous", label: "-ous", meaning: "full of" },
    { suffix: "ive", label: "-ive", meaning: "tending to" },
    { suffix: "ant", label: "-ant", meaning: "being, agent" },
    { suffix: "ent", label: "-ent", meaning: "being, agent" },
    { suffix: "ity", label: "-ity", meaning: "quality, state" },
    { suffix: "ize", label: "-ize", meaning: "make, cause to be" },
    { suffix: "ise", label: "-ise", meaning: "make, cause to be" },
    { suffix: "ify", label: "-ify", meaning: "make, transform" },
    { suffix: "ate", label: "-ate", meaning: "cause, characterized by" },
    { suffix: "ure", label: "-ure", meaning: "action, result" },
    { suffix: "ial", label: "-ial", meaning: "relating to" },
    { suffix: "al", label: "-al", meaning: "relating to" },
    { suffix: "ic", label: "-ic", meaning: "pertaining to" },
    { suffix: "ly", label: "-ly", meaning: "in the manner of" },
    { suffix: "ed", label: "-ed", meaning: "characterized by" },
    { suffix: "er", label: "-er", meaning: "agent, doer" },
    { suffix: "or", label: "-or", meaning: "agent, doer" }
];

var EN_ROOT_GLOSSES = {
    "spect": "look, see",
    "spec": "look, observe",
    "spic": "look, see",
    "dict": "say, speak",
    "duc": "lead",
    "duct": "lead, channel",
    "scrib": "write",
    "script": "write",
    "port": "carry",
    "fer": "carry, bear",
    "lat": "carry, bear",
    "mit": "send",
    "miss": "send",
    "ject": "throw",
    "tract": "draw, pull",
    "struct": "build",
    "rupt": "break, burst",
    "flect": "bend",
    "flex": "bend",
    "cred": "believe, trust",
    "cogn": "know",
    "gnit": "know",
    "sci": "know",
    "vid": "see",
    "vis": "see",
    "aud": "hear",
    "phon": "sound, voice",
    "graph": "write, record",
    "gram": "written mark",
    "chron": "time",
    "temp": "time",
    "loc": "place",
    "pos": "put, place",
    "pon": "put, place",
    "ten": "hold, keep",
    "tain": "hold, keep",
    "tin": "hold",
    "cap": "take, seize",
    "cept": "take, receive",
    "cip": "take",
    "fac": "make, do",
    "fect": "make, do",
    "fic": "make, do",
    "act": "drive, do",
    "ag": "drive, act",
    "ven": "come",
    "vent": "come",
    "ced": "go, yield",
    "cess": "go, yield",
    "grad": "step, go",
    "gress": "step, walk",
    "flu": "flow",
    "flux": "flow",
    "pend": "hang, weigh",
    "pens": "weigh, pay",
    "pel": "drive, push",
    "puls": "drive, push",
    "press": "press",
    "serv": "keep, protect",
    "stat": "stand",
    "sist": "stand",
    "stit": "stand, set up",
    "val": "be strong, worth",
    "viv": "live",
    "vit": "life",
    "bio": "life",
    "geo": "earth",
    "theo": "god, theory",
    "theor": "contemplate, observe",
    "path": "feeling, suffer",
    "phil": "love",
    "phob": "fear",
    "log": "word, study",
    "leg": "law / choose, read",
    "lect": "choose, read",
    "lig": "choose, bind",
    "rect": "straight, right",
    "reg": "rule, straight",
    "jur": "law, right",
    "just": "law, right",
    "man": "hand",
    "ped": "foot",
    "corp": "body",
    "psych": "mind, soul",
    "soci": "companion, society",
    "phys": "nature, body",
    "myth": "story, legend",
    "lum": "light",
    "luc": "light, clear",
    "clar": "clear, bright",
    "magn": "great, large",
    "min": "small, less",
    "ministr": "serve, manage",
    "equ": "equal, even",
    "ver": "true",
    "simil": "like, similar",
    "mut": "change",
    "nov": "new",
    "fin": "end, boundary",
    "term": "boundary, limit",
    "form": "shape",
    "part": "divide, share",
    "join": "connect",
    "junct": "join",
    "clos": "shut",
    "clud": "shut",
    "clus": "shut",
    "volv": "roll, turn",
    "vers": "turn",
    "vert": "turn"
};

var DE_PREFIX_RULES = [
    { prefix: "auseinander", label: "auseinander-", meaning: "apart from each other" },
    { prefix: "zusammen", label: "zusammen-", meaning: "together" },
    { prefix: "entgegen", label: "entgegen-", meaning: "toward, against" },
    { prefix: "gegenüber", label: "gegenüber-", meaning: "opposite" },
    { prefix: "heraus", label: "heraus-", meaning: "out from inside" },
    { prefix: "hinein", label: "hinein-", meaning: "into" },
    { prefix: "voraus", label: "voraus-", meaning: "in advance" },
    { prefix: "weiter", label: "weiter-", meaning: "further, continue" },
    { prefix: "wieder", label: "wieder-", meaning: "again" },
    { prefix: "wider", label: "wider-", meaning: "against, reflect" },
    { prefix: "unter", label: "unter-", meaning: "under, among" },
    { prefix: "über", label: "über-", meaning: "over, across" },
    { prefix: "durch", label: "durch-", meaning: "through" },
    { prefix: "hinter", label: "hinter-", meaning: "behind" },
    { prefix: "nach", label: "nach-", meaning: "after, following" },
    { prefix: "miss", label: "miss-", meaning: "wrongly, amiss" },
    { prefix: "fehl", label: "fehl-", meaning: "wrong, amiss" },
    { prefix: "voll", label: "voll-", meaning: "full, completely" },
    { prefix: "vor", label: "vor-", meaning: "before, ahead" },
    { prefix: "auf", label: "auf-", meaning: "up, open" },
    { prefix: "aus", label: "aus-", meaning: "out, thoroughly" },
    { prefix: "ein", label: "ein-", meaning: "in, into" },
    { prefix: "mit", label: "mit-", meaning: "with, co-" },
    { prefix: "bei", label: "bei-", meaning: "by, alongside" },
    { prefix: "dar", label: "dar-", meaning: "forth, present" },
    { prefix: "her", label: "her-", meaning: "hither, toward" },
    { prefix: "hin", label: "hin-", meaning: "thither, away" },
    { prefix: "los", label: "los-", meaning: "loose, away" },
    { prefix: "weg", label: "weg-", meaning: "away" },
    { prefix: "zer", label: "zer-", meaning: "apart, to pieces" },
    { prefix: "ent", label: "ent-", meaning: "away, begin, un-" },
    { prefix: "emp", label: "emp-", meaning: "toward, receive" },
    { prefix: "ver", label: "ver-", meaning: "transform, thoroughly" },
    { prefix: "be", label: "be-", meaning: "act upon, equip" },
    { prefix: "er", label: "er-", meaning: "achieve, emerge" },
    { prefix: "ge", label: "ge-", meaning: "collective / participle" },
    { prefix: "un", label: "un-", meaning: "not, opposite" },
    { prefix: "ur", label: "ur-", meaning: "original, primal" },
    { prefix: "ab", label: "ab-", meaning: "off, down, away" },
    { prefix: "an", label: "an-", meaning: "at, on, begin" },
    { prefix: "um", label: "um-", meaning: "around, change" },
    { prefix: "zu", label: "zu-", meaning: "to, closed" }
];

var DE_SUFFIX_RULES = [
    { suffix: "lichkeit", label: "-lichkeit", meaning: "quality, state" },
    { suffix: "igkeit", label: "-igkeit", meaning: "state, quality" },
    { suffix: "schaft", label: "-schaft", meaning: "collective state, domain" },
    { suffix: "barkeit", label: "-barkeit", meaning: "ability to be" },
    { suffix: "ieren", label: "-ieren", meaning: "verbal action" },
    { suffix: "keit", label: "-keit", meaning: "quality, state" },
    { suffix: "heit", label: "-heit", meaning: "abstract quality" },
    { suffix: "chen", label: "-chen", meaning: "diminutive" },
    { suffix: "lein", label: "-lein", meaning: "diminutive" },
    { suffix: "lich", label: "-lich", meaning: "characteristic of" },
    { suffix: "isch", label: "-isch", meaning: "pertaining to" },
    { suffix: "haft", label: "-haft", meaning: "having the nature of" },
    { suffix: "voll", label: "-voll", meaning: "full of" },
    { suffix: "los", label: "-los", meaning: "without" },
    { suffix: "bar", label: "-bar", meaning: "able to be" },
    { suffix: "sam", label: "-sam", meaning: "tending to" },
    { suffix: "ung", label: "-ung", meaning: "noun of action/result" },
    { suffix: "nis", label: "-nis", meaning: "result, state" },
    { suffix: "tum", label: "-tum", meaning: "domain, condition" },
    { suffix: "tät", label: "-tät", meaning: "academic quality" },
    { suffix: "ion", label: "-ion", meaning: "process, state" },
    { suffix: "ig", label: "-ig", meaning: "having, characterized by" },
    { suffix: "en", label: "-en", meaning: "verb infinitive" }
];

function inferMorphology(rawWord, language) {
    var w = String(rawWord || "").trim();
    if (!w) return [];
    var lang = String(language || "en").toLowerCase();
    if (lang === "de") {
        var parsedDe = parseGermanHeadword(w);
        var cleanDe = parsedDe.word.trim();
        var deCands = stemGerman(cleanDe);
        for (var i = 0; i < deCands.length; i++) {
            var deEntry = GERMAN_LEXICON[deCands[i]];
            if (deEntry && Array.isArray(deEntry.morphology) && deEntry.morphology.length > 0) {
                return deEntry.morphology.slice();
            }
        }
        var lowerDe = cleanDe.toLowerCase();
        var deParts = [];
        var remDe = lowerDe;
        for (var p = 0; p < DE_PREFIX_RULES.length; p++) {
            var pr = DE_PREFIX_RULES[p];
            if (remDe.indexOf(pr.prefix) === 0 && remDe.length - pr.prefix.length >= 3) {
                deParts.push({ part: pr.label, kind: "prefix", meaning: pr.meaning });
                remDe = remDe.slice(pr.prefix.length);
                break;
            }
        }
        var matchedDeSuffix = null;
        for (var s = 0; s < DE_SUFFIX_RULES.length; s++) {
            var sr = DE_SUFFIX_RULES[s];
            if (remDe.length - sr.suffix.length >= 3 && remDe.slice(-sr.suffix.length) === sr.suffix) {
                matchedDeSuffix = { part: sr.label, kind: "suffix", meaning: sr.meaning };
                remDe = remDe.slice(0, -sr.suffix.length);
                break;
            }
        }
        deParts.push({ part: remDe || cleanDe, kind: "root", meaning: "core stem" });
        if (matchedDeSuffix) deParts.push(matchedDeSuffix);
        return deParts;
    }

    // English morphology lookup or decomposition
    var cleanEn = w.replace(/^to\s+/i, "").trim();
    var enCands = stemEnglish(cleanEn);
    for (var j = 0; j < enCands.length; j++) {
        var enEntry = ENGLISH_LEXICON[enCands[j]];
        if (enEntry && Array.isArray(enEntry.morphology) && enEntry.morphology.length > 0) {
            return enEntry.morphology.slice();
        }
    }

    var lowerEn = cleanEn.toLowerCase();
    var enParts = [];
    var remEn = lowerEn;
    for (var ep = 0; ep < EN_PREFIX_RULES.length; ep++) {
        var epr = EN_PREFIX_RULES[ep];
        if (remEn.indexOf(epr.prefix) === 0 && remEn.length - epr.prefix.length >= 3) {
            enParts.push({ part: epr.label, kind: "prefix", meaning: epr.meaning });
            remEn = remEn.slice(epr.prefix.length);
            break;
        }
    }
    var matchedEnSuffix = null;
    for (var es = 0; es < EN_SUFFIX_RULES.length; es++) {
        var esr = EN_SUFFIX_RULES[es];
        if (remEn.length - esr.suffix.length >= 3 && remEn.slice(-esr.suffix.length) === esr.suffix) {
            matchedEnSuffix = { part: esr.label, kind: "suffix", meaning: esr.meaning };
            remEn = remEn.slice(0, -esr.suffix.length);
            break;
        }
    }
    var rootMeaning = EN_ROOT_GLOSSES[remEn] || "";
    if (!rootMeaning) {
        var rootKeys = Object.keys(EN_ROOT_GLOSSES);
        for (var rk = 0; rk < rootKeys.length; rk++) {
            var rKey = rootKeys[rk];
            if (rKey.length >= 3 && remEn.indexOf(rKey) >= 0) {
                rootMeaning = EN_ROOT_GLOSSES[rKey];
                break;
            }
        }
    }
    enParts.push({ part: remEn || cleanEn, kind: "root", meaning: rootMeaning || "core root" });
    if (matchedEnSuffix) enParts.push(matchedEnSuffix);
    return enParts;
}

function withLexicalAliases(obj, isFound) {
    obj.headword = obj.word || "";
    obj.cefrLevel = obj.level || "";
    obj.cefrSource = obj.levelSource || "";
    obj.phonetics = obj.phonetic || "";
    obj.gender = obj.article || "";
    obj.definition = obj.meaning || "";
    obj.definitionEn = obj.definitionEn || obj.meaning || "";
    obj.meaningVi = obj.meaningVi || "";
    obj.collocations = Array.isArray(obj.collocations) ? obj.collocations : [];
    obj.morphology = Array.isArray(obj.morphology) ? obj.morphology : [];
    obj.morphologyText = obj.morphologyText || formatMorphology(obj.morphology);
    obj.found = Boolean(isFound);
    return obj;
}

function analyzeTerm(rawTerm, preferredLanguage) {
    var raw = String(rawTerm || "").trim();
    if (!raw) {
        return withLexicalAliases({
            word: "",
            displayTerm: "",
            language: preferredLanguage || "en",
            level: "",
            levelSource: "",
            levelConfidence: "none",
            pos: "",
            phonetic: "",
            article: "",
            plural: "",
            meaning: "",
            meaningVi: "",
            example: "",
            collocations: [],
            synonyms: [],
            antonyms: [],
            morphology: [],
            morphologyText: ""
        }, false);
    }

    var lang = detectLanguage(raw, preferredLanguage);
    var parsedDe = lang === "de" ? parseGermanHeadword(raw) : { word: raw, article: "", plural: "", preposition: "" };
    var cleanWord = parsedDe.word.trim();
    var prepSuffix = parsedDe.preposition ? (" " + parsedDe.preposition) : "";

    if (lang === "de") {
        var deCandidates = stemGerman(cleanWord);
        for (var i = 0; i < deCandidates.length; i++) {
            var entryDe = GERMAN_LEXICON[deCandidates[i]];
            if (entryDe) {
                var effectivePos = entryDe.pos || inferPartOfSpeech(cleanWord, "de", parsedDe.article || entryDe.article || "");
                var art = parsedDe.article || entryDe.article || (effectivePos === "noun" ? inferGermanArticle(entryDe.word) : "");
                var pl = parsedDe.plural || entryDe.plural || "";
                var baseDeWord = entryDe.word || cleanWord;
                var deMorph = Array.isArray(entryDe.morphology) && entryDe.morphology.length
                    ? entryDe.morphology.slice()
                    : inferMorphology(baseDeWord, "de");
                return withLexicalAliases({
                    word: baseDeWord + prepSuffix,
                    displayTerm: (art ? art + " " : "") + baseDeWord + prepSuffix,
                    language: "de",
                    level: entryDe.level,
                    levelSource: entryDe.source,
                    levelConfidence: "verified",
                    pos: effectivePos,
                    phonetic: entryDe.phonetic || "",
                    article: art,
                    plural: pl,
                    meaning: entryDe.meaning || "",
                    meaningVi: entryDe.meaningVi || "",
                    example: entryDe.example || "",
                    collocations: entryDe.collocations ? entryDe.collocations.slice() : [],
                    synonyms: entryDe.synonyms ? entryDe.synonyms.slice() : [],
                    antonyms: entryDe.antonyms ? entryDe.antonyms.slice() : [],
                    morphology: deMorph,
                    morphologyText: formatMorphology(deMorph)
                }, true);
            }
        }
        var inferredArt = parsedDe.article || inferGermanArticle(cleanWord);
        var deEst = estimateCefrHeuristic(cleanWord, "de");
        var deFallbackMorph = inferMorphology(cleanWord, "de");
        return withLexicalAliases({
            word: cleanWord + prepSuffix,
            displayTerm: (inferredArt ? inferredArt + " " : "") + cleanWord + prepSuffix,
            language: "de",
            level: deEst.level,
            levelSource: deEst.source,
            levelConfidence: deEst.confidence,
            pos: inferPartOfSpeech(cleanWord, "de", inferredArt),
            phonetic: "",
            article: inferredArt,
            plural: parsedDe.plural || "",
            meaning: "",
            meaningVi: "",
            example: "",
            collocations: [],
            synonyms: [],
            antonyms: [],
            morphology: deFallbackMorph,
            morphologyText: formatMorphology(deFallbackMorph)
        }, true);
    }

    // English or general
    var enCandidates = stemEnglish(cleanWord);
    for (var j = 0; j < enCandidates.length; j++) {
        var entryEn = ENGLISH_LEXICON[enCandidates[j]];
        if (entryEn) {
            var enMorph = Array.isArray(entryEn.morphology) && entryEn.morphology.length
                ? entryEn.morphology.slice()
                : inferMorphology(cleanWord, "en");
            return withLexicalAliases({
                word: cleanWord,
                displayTerm: cleanWord,
                language: lang === "other" || lang === "general" ? lang : "en",
                level: entryEn.level,
                levelSource: entryEn.source,
                levelConfidence: "verified",
                pos: entryEn.pos || inferPartOfSpeech(cleanWord, "en", ""),
                phonetic: entryEn.phonetic || "",
                article: "",
                plural: "",
                meaning: entryEn.meaning || "",
                meaningVi: entryEn.meaningVi || "",
                example: entryEn.example || "",
                collocations: entryEn.collocations ? entryEn.collocations.slice() : [],
                synonyms: entryEn.synonyms ? entryEn.synonyms.slice() : [],
                antonyms: entryEn.antonyms ? entryEn.antonyms.slice() : [],
                morphology: enMorph,
                morphologyText: formatMorphology(enMorph)
            }, true);
        }
    }

    var enEst = estimateCefrHeuristic(cleanWord, "en");
    var enFallbackMorph = inferMorphology(cleanWord, "en");
    return withLexicalAliases({
        word: cleanWord,
        displayTerm: cleanWord,
        language: lang,
        level: enEst.level,
        levelSource: enEst.source,
        levelConfidence: enEst.confidence,
        pos: inferPartOfSpeech(cleanWord, "en", ""),
        phonetic: "",
        article: "",
        plural: "",
        meaning: "",
        example: "",
        collocations: [],
        synonyms: [],
        antonyms: [],
        morphology: enFallbackMorph,
        morphologyText: formatMorphology(enFallbackMorph)
    }, true);
}

function mergeOnlineLookup(localAnalysis, onlinePayload) {
    var base = Object.assign({}, localAnalysis || {});
    if (!onlinePayload || typeof onlinePayload !== "object" || (!onlinePayload.ok && !onlinePayload.found && !onlinePayload.cefrLevel && !onlinePayload.level)) {
        return withLexicalAliases(base, Boolean(base.word));
    }
    var rawOnlineLevel = String(onlinePayload.level || onlinePayload.cefrLevel || "").toUpperCase();
    var onlineSource = String(onlinePayload.levelSource || onlinePayload.cefrSource || "");
    var isOnlineHeuristic = /Heuristic/i.test(onlineSource) && !onlinePayload.onlineVerified;
    var keepLocalLevel = Boolean(base.level) && (base.levelConfidence === "verified" || isOnlineHeuristic);
    var validLevel = keepLocalLevel
        ? base.level
        : (CEFR_LEVELS.indexOf(rawOnlineLevel) >= 0 ? rawOnlineLevel : base.level);
    var effectiveSource = keepLocalLevel
        ? (base.levelSource || onlineSource || "Dictionary")
        : (onlineSource || base.levelSource || "Online Dictionary");
    var mergedPos = String((base.levelConfidence === "verified" && base.pos) ? base.pos : (onlinePayload.pos || base.pos || "")).toLowerCase();
    if (mergedPos === "adjective") mergedPos = "adj";
    if (mergedPos === "adverb") mergedPos = "adv";
    var mergedArticle = String(onlinePayload.article || onlinePayload.gender || base.article || "").trim();
    if (mergedPos && mergedPos !== "noun" && mergedPos !== "n" && mergedPos !== "word" && mergedArticle.toLowerCase() !== "sich") {
        mergedArticle = "";
    }
    var mergedWord = String(base.word || onlinePayload.word || onlinePayload.headword || "");
    var mergedDisplayTerm = mergedArticle
        ? (mergedArticle + " " + mergedWord)
        : mergedWord;
    var mergedMorph = (base.levelConfidence === "verified" && Array.isArray(base.morphology) && base.morphology.length)
        ? base.morphology
        : (Array.isArray(onlinePayload.morphology) && onlinePayload.morphology.length
            ? onlinePayload.morphology
            : (Array.isArray(base.morphology) ? base.morphology : []));
    var mergedMorphText = formatMorphology(mergedMorph) || String(onlinePayload.morphologyText || base.morphologyText || "");
    return withLexicalAliases({
        word: mergedWord,
        displayTerm: mergedDisplayTerm,
        language: String(onlinePayload.language || base.language || "en"),
        level: validLevel || "B1",
        levelSource: effectiveSource,
        levelConfidence: (!isOnlineHeuristic && rawOnlineLevel) ? "verified" : (base.levelConfidence || "medium"),
        pos: mergedPos,
        phonetic: String(onlinePayload.phonetic || onlinePayload.phonetics || base.phonetic || ""),
        article: mergedArticle,
        plural: String(onlinePayload.plural || base.plural || ""),
        meaning: String((base.levelConfidence === "verified" && base.meaning) ? base.meaning : (onlinePayload.meaning || onlinePayload.definition || base.meaning || "")),
        meaningVi: String(base.meaningVi || onlinePayload.meaningVi || ""),
        example: String((base.levelConfidence === "verified" && base.example) ? base.example : (onlinePayload.example || base.example || "")),
        collocations: Array.isArray(base.collocations) && base.collocations.length
            ? base.collocations
            : (Array.isArray(onlinePayload.collocations) ? onlinePayload.collocations : []),
        synonyms: Array.isArray(onlinePayload.synonyms) && onlinePayload.synonyms.length && (!Array.isArray(base.synonyms) || !base.synonyms.length)
            ? onlinePayload.synonyms.slice(0, 6)
            : (base.synonyms && base.synonyms.length ? base.synonyms : (onlinePayload.synonyms ? onlinePayload.synonyms.slice(0, 6) : [])),
        antonyms: Array.isArray(onlinePayload.antonyms) && onlinePayload.antonyms.length && (!Array.isArray(base.antonyms) || !base.antonyms.length)
            ? onlinePayload.antonyms.slice(0, 6)
            : (base.antonyms && base.antonyms.length ? base.antonyms : (onlinePayload.antonyms ? onlinePayload.antonyms.slice(0, 6) : [])),
        morphology: mergedMorph,
        morphologyText: mergedMorphText
    }, true);
}
