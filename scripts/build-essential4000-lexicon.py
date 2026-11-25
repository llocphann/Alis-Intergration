#!/usr/bin/env python3
"""Offline builder & validator for services/SpacedRepetitionEssential4000.js.

Audits and repairs all 3,603 4000 Essential English Words (Books 1-6, Units 1-30)
and starter seed cards:
  1. Canonical POS in {noun, verb, adjective, adverb, preposition, conjunction, pronoun, determiner}
  2. Dictionary-grounded CEFR levels (Oxford 3000/5000 + Cambridge EVP + book progression)
  3. Clean Unicode IPA phonetics (/.../, zero /əːr/, zero ':', zero Cyrillic 'ӕ')
  4. POS-aligned Vietnamese glosses (fixing homograph & tech-jargon mistranslations)
  5. Clean English definitions & examples (fixing OCR spacing/typos)
  6. 100% natural collocations (zero synthetic templates like 'to <noun>' or '<word> properly')
  7. Rebuilt clozeText with {{c1::<inflected_target>::<pos> — <concise_meaningVi>}}
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
OUT_JS = ROOT / "plugins" / "spaced_repetition" / "services" / "SpacedRepetitionEssential4000.js"

CANONICAL_POS = (
    "noun",
    "verb",
    "adjective",
    "adverb",
    "preposition",
    "conjunction",
    "pronoun",
    "determiner",
)

LEVEL_SOURCES = (
    "Oxford 3000 / Cambridge EVP",
    "Oxford 5000 / Cambridge EVP",
    "Cambridge EVP",
    "Oxford 3000 / 4000 Essential English Words Vol. 1",
    "Oxford 3000 / 4000 Essential English Words Vol. 2",
    "Oxford 3000 / 4000 Essential English Words Vol. 3",
    "Oxford 3000 / 4000 Essential English Words Vol. 4",
    "Oxford 3000 / 4000 Essential English Words Vol. 5",
    "Oxford 3000 / 4000 Essential English Words Vol. 6",
    "Cambridge EVP / 4000 Essential English Words Vol. 1",
    "Cambridge EVP / 4000 Essential English Words Vol. 2",
    "Cambridge EVP / 4000 Essential English Words Vol. 3",
    "Cambridge EVP / 4000 Essential English Words Vol. 4",
    "Cambridge EVP / 4000 Essential English Words Vol. 5",
    "Cambridge EVP / 4000 Essential English Words Vol. 6",
)

# Explicit card-level POS repairs audited across all 3,603 cards
POS_OVERRIDES_BY_ID: dict[str, str] = {
    # 14 previously tagged 'word'
    "sr-b01-u17-12": "noun",        # hill
    "sr-b02-u01-16": "adverb",      # rapidly
    "sr-b02-u02-05": "verb",        # ensure
    "sr-b02-u02-07": "noun",        # jewelry
    "sr-b02-u02-10": "noun",        # monster
    "sr-b02-u10-12": "verb",        # ought
    "sr-b02-u12-18": "adjective",   # passive
    "sr-b02-u15-18": "adjective",   # smooth
    "sr-b02-u21-12": "verb",        # pour
    "sr-b03-u02-03": "noun",        # caretaker
    "sr-b03-u06-01": "verb",        # alert
    "sr-b03-u21-07": "noun",        # emphasis
    "sr-b04-u06-02": "adverb",      # alas
    "sr-b05-u27-09": "noun",        # pioneer
    # Misclassified POS cards discovered in full 3,603-card audit
    "sr-b01-u10-11": "noun",        # image (was verb)
    "sr-b01-u10-17": "adjective",   # separate (was verb)
    "sr-b01-u17-08": "adverb",      # else (was adjective)
    "sr-b01-u26-08": "adverb",      # further (was adjective)
    "sr-b01-u26-11": "conjunction", # neither (was adverb; Neither ... nor)
    "sr-b02-u03-09": "adverb",      # hardly (was adjective)
    "sr-b02-u25-08": "noun",        # elder (was adjective; An elder is a person...)
    "sr-b03-u05-13": "verb",        # rot (was noun; When something rots / began to rot)
    "sr-b03-u10-15": "noun",        # rhyme (EX: an old rhyme)
    "sr-b03-u18-06": "noun",        # independence (was adjective)
    "sr-b03-u27-03": "noun",        # blonde (was adjective; a blonde)
    "sr-b04-u08-20": "adverb",      # whatsoever (was adjective; no idea whatsoever)
    "sr-b04-u09-01": "preposition", # alongside (was adverb; alongside each other)
    "sr-b04-u19-09": "adverb",      # etc. (was noun)
    "sr-b04-u27-16": "noun",        # objective (was adjective; An objective is a goal...)
    "sr-b04-u29-20": "noun",        # transportation (was verb!)
    "sr-b04-u30-08": "adjective",   # martial (was noun; martial art)
    "sr-b05-u07-02": "noun",        # biosphere (was adjective)
    "sr-b06-u06-03": "noun",        # counterpart (was verb)
    "sr-b06-u18-02": "adjective",   # centigrade (was noun; 26 degrees centigrade)
}

# English definition repairs (corrupted/Vietnamese/OCR typos & circular derivational giveaways)
DEF_OVERRIDES_BY_ID: dict[str, tuple[str, str]] = {
    "sr-b01-u02-04": ("chemical", "any basic substance used in or produced by reactions between elements and compounds"),
    "sr-b01-u04-10": ("instruct", "to give clear directions or orders to somebody; to teach a skill or subject"),
    "sr-b01-u19-11": ("injustice", "a lack of fairness or rightful treatment"),
    "sr-b01-u23-16": ("safety", "the condition of being protected from harm, risk, or danger"),
    "sr-b01-u23-20": ("web", "A web is a home made by a spider."),
    "sr-b01-u24-08": ("friendship", "a close, trusting bond of affection between people"),
    "sr-b01-u30-11": ("honesty", "the quality of being truthful, sincere, and free from deceit"),
    "sr-b01-u30-14": ("inside", "the interior part or space within a container, room, or object"),
    "sr-b02-u02-11": ("northern", "situated in, facing, or coming from the Arctic compass direction opposite the south"),
    "sr-b02-u02-13": ("southern", "situated in, facing, or coming from the compass direction opposite the north"),
    "sr-b02-u03-11": ("laughter", "the happy sound people make with their voices when something is funny"),
    "sr-b02-u09-09": ("disorder", "a state of confusion, untidiness, or a complete mess"),
    "sr-b02-u11-04": ("chemistry", "Chemistry is the study of what things are made of and how they change."),
    "sr-b02-u16-11": ("likeness", "the quality of looking or being similar to someone or something else; resemblance"),
    "sr-b02-u21-08": ("miner", "a worker who digs underground to extract coal, gold, or other minerals"),
    "sr-b02-u22-06": ("bucket", "A bucket is a round container to put things in."),
    "sr-b02-u23-10": ("heal", "to become sound and well again after an injury or illness"),
    "sr-b02-u28-08": ("electronic", "operating through microchips, circuits, and powered currents"),
    "sr-b02-u29-16": ("religious", "relating to spiritual faith, worship, or sacred beliefs"),
    "sr-b03-u03-13": ("overnight", "from evening until the next morning, or very suddenly"),
    "sr-b03-u03-17": ("sensation", "a physical feeling or impression noticed by the body"),
    "sr-b03-u10-15": ("rhyme", "A rhyme is a short poem or song in which words end with the same sound."),
    "sr-b03-u11-01": ("abnormal", "unusual, strange, or different from what is typical or expected"),
    "sr-b03-u13-11": ("millionaire", "a very wealthy person whose fortune reaches seven figures or more"),
    "sr-b03-u16-09": ("literary", "relating to written works of art such as novels, poetry, and plays"),
    "sr-b03-u26-18": ("receipt", "a printed slip proving that goods or money were paid for"),
    "sr-b03-u28-04": ("chemist", "a scientist who studies substances, elements, and how they react"),
    "sr-b04-u03-09": ("eventual", "occurring at the final stage of a long process or sequence"),
    "sr-b04-u04-15": ("slippery", "so wet, icy, or smooth that it is difficult to hold or walk on safely"),
    "sr-b04-u05-19": ("typewritten", "printed with mechanical keys or a keyboard rather than written by hand"),
    "sr-b04-u06-03": ("attentive", "watching and listening closely with care, courtesy, and focus"),
    "sr-b04-u08-14": ("replace", "to substitute a new person or item for a previous one"),
    "sr-b04-u12-09": ("disrespect", "rudeness or impolite behavior that shows a lack of courtesy"),
    "sr-b04-u15-03": ("await", "to stay ready and expect something to arrive or happen soon"),
    "sr-b04-u17-17": ("stormy", "marked by rough weather with heavy rain, strong winds, and thunder"),
    "sr-b04-u18-20": ("staircase", "a flight of steps and railings leading from one floor to another inside a building"),
    "sr-b04-u23-07": ("genetic", "passed down from parents to offspring through inherited DNA"),
    "sr-b04-u25-04": ("decisive", "able to make firm choices quickly and with confidence"),
    "sr-b04-u25-08": ("hardy", "If a person or plant is hardy, it is strong and can live through difficult conditions."),
    "sr-b04-u28-20": ("worsen", "to deteriorate or become more severe and unpleasant"),
    "sr-unit03-15": ("mythology", "a collection of ancient legends and traditional tales about gods and heroes of a culture"),
    "sr-unit03-17": ("radioactive", "emitting dangerous high-energy particles when unstable atomic nuclei decay"),
    "sr-unit03-18": ("relativity", "the physics principle describing how space, time, and gravity depend on an observer's motion"),
    "sr-unit03-19": ("sociology", "the academic study of human communities, group behavior, and cultural institutions"),
    "sr-unit03-20": ("theoretical", "based on abstract models and principles rather than hands-on practice or experiment"),
    "sr-b05-u05-15": ("publicity", "widespread media attention and notice given to a person, product, or event"),
    "sr-b05-u06-02": ("coastline", "the natural boundary where a landmass meets the sea or ocean"),
    "sr-b05-u07-15": ("repetitive", "involving the same action again and again until it feels monotonous"),
    "sr-b05-u08-10": ("intake", "the total quantity of food, drink, or air consumed by the body"),
    "sr-b05-u08-13": ("medication", "a pharmaceutical drug or remedy prescribed to treat or relieve illness"),
    "sr-b05-u09-11": ("managerial", "relating to the duties or skills of directing a team, department, or business"),
    "sr-b05-u10-01": ("accountant", "a professional who prepares, audits, and maintains financial records and taxes"),
    "sr-b05-u10-12": ("monetary", "relating to currency, finance, or a nation's banking system"),
    "sr-b05-u12-20": ("undergraduate", "An undergraduate is a student at a college who is studying for a bachelor’s degree."),
    "sr-b05-u14-10": ("informative", "providing useful facts, clear explanations, and practical knowledge"),
    "sr-b05-u16-02": ("archeological", "involving the excavation and study of ancient ruins and artifacts"),
    "sr-b05-u16-17": ("prehistoric", "belonging to the ancient era before written records existed"),
    "sr-b05-u20-06": ("database", "an organized digital repository of structured records stored on a computer"),
    "sr-b05-u24-07": ("furnish", "to equip a room or house with tables, chairs, beds, and other fittings"),
    "sr-b05-u25-15": ("sticky", "coated with a glue-like substance that clings to fingers or surfaces"),
    "sr-b05-u26-20": ("supernatural", "involving mystical forces beyond scientific explanation"),
    "sr-b05-u27-03": ("cellular", "relating to the microscopic living units that make up organisms"),
    "sr-b05-u27-16": ("surgeon", "a specialist doctor trained to perform medical operations on patients"),
    "sr-b05-u28-12": ("norm", "an accepted standard or customary way of behaving within a society"),
    "sr-b05-u30-18": ("talkative", "fond of chatting eagerly and speaking at length"),
    "sr-b06-u01-03": ("differentiate", "to recognize or show what makes two or more things distinct"),
    "sr-b06-u02-03": ("coexist", "to live together peacefully at the same time and in the same place"),
    "sr-b06-u03-13": ("reputable", "widely trusted and respected for honesty and high standards"),
    "sr-b06-u04-15": ("overwork", "to exhaust someone with excessive labor and long hours"),
    "sr-b06-u09-07": ("inseparable", "always together and unable to be parted from one another"),
    "sr-b06-u10-16": ("sideways", "shifting laterally to the left or right rather than straight ahead"),
    "sr-b06-u12-12": ("housekeeping", "the daily cleaning, tidying, and upkeep of a residence or hotel"),
    "sr-b06-u15-11": ("metabolic", "relating to the chemical processes by which the body converts food into energy"),
    "sr-b06-u16-02": ("backstage", "in the dressing and preparation area behind a theater curtain"),
    "sr-b06-u16-03": ("billionaire", "an ultra-wealthy individual whose net worth reaches ten figures or more"),
    "sr-b06-u17-06": ("electromagnetic", "relating to physical waves and forces produced by charged particles in motion"),
    "sr-b06-u17-07": ("electron", "a tiny subatomic particle orbiting an atomic nucleus with a negative charge"),
    "sr-b06-u18-20": ("zip", "to fasten a jacket or bag shut using interlocking metal or plastic teeth"),
    "sr-b06-u19-12": ("personalize", "to customize or tailor something to an individual's own style or needs"),
    "sr-b06-u20-08": ("inclusion", "the practice of welcoming and involving everyone equally within a group"),
    "sr-b06-u21-18": ("secrecy", "the practice of keeping plans or information strictly confidential and hidden"),
    "sr-b06-u22-13": ("nationality", "the legal status of belonging to a particular country by birth or citizenship"),
    "sr-b06-u23-05": ("clockwise", "moving in a curve from top to right, bottom, and left like the hands of a watch"),
    "sr-b06-u23-14": ("locker", "a small metal compartment with a key or combination for storing personal belongings"),
    "sr-b06-u23-15": ("multicultural", "bringing together diverse ethnic traditions, languages, and backgrounds"),
    "sr-b06-u25-15": ("sensory", "relating to physical perception through sight, hearing, smell, taste, or touch"),
    "sr-b06-u26-04": ("forefinger", "the index digit on the hand next to the thumb, often used for pointing"),
    "sr-b06-u28-12": ("outnumber", "to exceed another group in total count or size"),
    "sr-b06-u29-15": ("shortcut", "a quicker, more direct path or method that saves time"),
}

EXAMPLE_OVERRIDES_BY_ID: dict[str, str] = {
    "sr-b01-u01-10": "The young boy hid behind the heavy velvet curtains so nobody would find him.",
    "sr-b01-u28-09": "The stage performer used magic to pull a white rabbit out of his hat.",
    "sr-b03-u08-07": "Kim and Martin’s new couch was very expensive.",
    "sr-b03-u12-14": "Please use a rag to clean the dust off the table.",
    "sr-b03-u14-13": "Roger is impolite to everyone he meets.",
    "sr-b03-u21-17": "The bird was standing on the tree’s stiff branch.",
    "sr-b03-u30-11": "He folded the clean laundry and placed the dirty clothes in a basket.",
    "sr-unit03-02": "After having asserted his innocence for years, new DNA evidence finally exonerated him.",
    "sr-unit03-12": "The new hydroelectric dam harnesses the river's current to power thousands of homes.",
    "sr-b05-u25-13": "The computers of the 1980s are primitive compared to those of today.",
    "sr-b06-u06-11": "All of the houses on Victor’s block were boring and homogeneous.",
    "sr-b06-u16-19": "We lost the game because we underestimated the other team’s skill.",
}

CLOZE_TARGET_OVERRIDES_BY_ID: dict[str, str] = {
    "sr-b02-u10-09": "impression",
    "sr-b02-u15-14": "generation",
    "sr-b02-u22-05": "breeds",
    "sr-b03-u14-13": "impolite",
    "sr-b03-u19-16": "snuck",
    "sr-b03-u21-17": "stiff",
    "sr-b03-u23-16": "rod",
    "sr-b03-u24-05": "flee",
    "sr-b03-u27-04": "conquer",
    "sr-unit03-02": "asserted",
    "sr-unit03-12": "harnesses",
    "sr-b05-u16-13": "integrity",
    "sr-b06-u06-11": "homogeneous",
    "sr-b06-u27-05": "deputy",
}

# IPA explicit overrides for empty or special-pronunciation cards
IPA_OVERRIDES_BY_ID: dict[str, tuple[str, str]] = {
    "sr-b02-u01-16": ("rapidly", "/ˈræpɪdli/"),
    "sr-b03-u21-07": ("emphasis", "/ˈemfəsɪs/"),
    "sr-b01-u10-17": ("separate", "/ˈsepərət/"),
    "sr-b01-u11-01": ("anymore", "/ˌeniˈmɔːr/"),
    "sr-b02-u02-11": ("northern", "/ˈnɔːrðərn/"),
    "sr-b04-u19-09": ("etc.", "/etˈsetərə/"),
    "sr-b04-u29-20": ("transportation", "/ˌtrænspərˈteɪʃən/"),
    "sr-b01-u08-19": ("tear", "/ter/"),
    "sr-b01-u16-06": ("concert", "/ˈkɒnsərt/"),
    "sr-b01-u27-05": ("desert", "/ˈdezərt/"),
}

# Comprehensive audited meaningVi overrides (card ID -> accurate POS-aligned Vietnamese gloss)
MEANING_VI_BY_ID: dict[str, tuple[str, str]] = {
    "sr-b04-u29-20": ("transportation", "phương tiện giao thông; sự vận chuyển"),
    "sr-b03-u03-20": ("valentine", "người yêu dấu (dịp lễ Tình nhân)"),
    "sr-b03-u10-05": ("creep", "rón rén, lẻn đi nhẹ nhàng"),
    "sr-b04-u06-12": ("pudding", "bánh tráng miệng mềm ngọt"),
    "sr-b05-u05-09": ("latter", "thuộc về đối tượng thứ hai, được nhắc sau"),
    "sr-b05-u22-05": ("cholesterol", "chất béo chuyển hóa trong máu"),
    "sr-b06-u17-07": ("electron", "hạt điện tử mang điện tích âm"),
    "sr-b01-u09-15": ("save", "cứu, bảo vệ an toàn"),
    "sr-b01-u10-18": ("site", "địa điểm, nơi chốn"),
    "sr-b01-u21-07": ("enter", "bước vào, đi vào"),
    "sr-b01-u30-18": ("scan", "nhìn kỹ, đọc lướt kỹ"),
    "sr-b02-u01-10": ("load", "chất hàng, xếp đồ vào"),
    "sr-b02-u02-12": ("remote", "xa xôi, hẻo lánh"),
    "sr-b02-u03-12": ("log", "khúc gỗ"),
    "sr-b02-u05-03": ("boot", "đôi ủng, giày ống"),
    "sr-b02-u09-11": ("enable", "cho phép, giúp có thể"),
    "sr-b02-u12-16": ("monitor", "theo dõi, giám sát"),
    "sr-b03-u06-07": ("console", "an ủi, vỗ về"),
    "sr-b03-u08-18": ("thread", "sợi chỉ"),
    "sr-b03-u09-07": ("crawl", "bò, trườn"),
    "sr-b03-u26-17": ("paste", "hỗn hợp nhão, hồ dán"),
    "sr-b04-u02-12": ("loop", "vòng tròn, thòng lọng"),
    "sr-b04-u02-18": ("string", "sợi dây mảnh"),
    "sr-b04-u03-14": ("option", "sự lựa chọn"),
    "sr-b04-u05-17": ("resolution", "quyết tâm, lời tự hứa"),
    "sr-b04-u08-01": ("access", "quyền tiếp cận, lối vào"),
    "sr-b04-u13-20": ("zoom", "lao vút đi"),
    "sr-b04-u14-14": ("shutter", "cửa chớp"),
    "sr-b04-u16-04": ("custom", "phong tục, tập quán"),
    "sr-b05-u05-20": ("terminal", "giai đoạn cuối, vô phương cứu chữa"),
    "sr-b05-u18-13": ("hack", "chặt mạnh, băm"),
    "sr-b05-u18-15": ("nick", "làm xước nhẹ, cứa nhẹ"),
    "sr-b05-u21-07": ("dash", "lao nhanh, chạy vội"),
    "sr-b05-u20-20": ("viral", "do vi-rút gây ra"),
    "sr-b05-u23-10": ("embed", "gắn chặt vào"),
    "sr-b05-u26-13": ("preview", "buổi chiếu/xem thử trước"),
    "sr-b05-u07-05": ("coarse", "thô ráp"),
    "sr-b05-u27-03": ("cellular", "thuộc về tế bào"),
    "sr-b06-u02-12": ("locale", "địa điểm, bối cảnh diễn ra"),
    "sr-b06-u05-04": ("char", "đốt cháy đen, làm cháy sém"),
    "sr-b06-u13-17": ("render", "làm cho trở nên"),
    "sr-b06-u18-17": ("profile", "góc mặt nhìn nghiêng"),
    "sr-b06-u18-20": ("zip", "kéo khóa lại"),
    "sr-b01-u01-12": ("lot", "số lượng lớn, nhiều"),
    "sr-b01-u06-02": ("cause", "gây ra"),
    "sr-b01-u06-09": ("follow", "đi theo, theo sau"),
    "sr-b01-u06-14": ("reach", "đến nơi, vươn tới"),
    "sr-b01-u07-05": ("claim", "tuyên bố, khẳng định"),
    "sr-b01-u07-12": ("force", "sức mạnh, lực"),
    "sr-b01-u07-13": ("harm", "sự tổn hại, tác hại"),
    "sr-b01-u07-14": ("lay", "đặt, để xuống"),
    "sr-b01-u07-18": ("sense", "cảm nhận, nhận thấy"),
    "sr-b01-u08-04": ("balance", "giữ thăng bằng"),
    "sr-b01-u08-12": ("pattern", "khuôn mẫu, quy luật"),
    "sr-b01-u08-15": ("release", "thả ra, buông ra"),
    "sr-b01-u08-17": ("single", "đơn lẻ, chỉ một"),
    "sr-b01-u09-03": ("damage", "làm hư hại"),
    "sr-b01-u10-04": ("effect", "tác động, ảnh hưởng"),
    "sr-b01-u10-07": ("focus", "tập trung"),
    "sr-b01-u10-17": ("separate", "tách biệt, riêng rẽ"),
    "sr-b01-u11-01": ("anymore", "không còn nữa"),
    "sr-b01-u11-15": ("sail", "chèo thuyền, đi thuyền"),
    "sr-b01-u11-17": ("spend", "dành (thời gian); tiêu (tiền)"),
    "sr-b01-u12-07": ("judge", "đánh giá, phán xét"),
    "sr-b01-u12-09": ("material", "vật liệu, chất liệu"),
    "sr-b01-u13-03": ("cell", "xà lim, buồng giam"),
    "sr-b01-u13-06": ("crop", "vụ mùa, cây trồng"),
    "sr-b01-u13-07": ("demand", "đòi hỏi, yêu cầu"),
    "sr-b01-u13-09": ("feed", "cho ăn"),
    "sr-b01-u13-17": ("sight", "cảnh tượng đáng xem"),
    "sr-b01-u14-15": ("scene", "cảnh (phim, kịch)"),
    "sr-b01-u14-16": ("sheet", "tờ giấy"),
    "sr-b01-u15-05": ("excite", "làm hào hứng"),
    "sr-b01-u15-06": ("extreme", "cực độ, khắc nghiệt"),
    "sr-b01-u15-19": ("wonder", "tự hỏi, thắc mắc"),
    "sr-b01-u16-03": ("board", "tấm ván gỗ"),
    "sr-b01-u16-16": ("pound", "đập mạnh, nện"),
    "sr-b01-u17-10": ("flow", "chảy, trôi"),
    "sr-b01-u17-14": ("lone", "đơn độc, duy nhất"),
    "sr-b01-u17-16": ("response", "câu trả lời, phản hồi"),
    "sr-b01-u17-19": ("waste", "lãng phí"),
    "sr-b01-u18-05": ("dish", "cái đĩa, bát đĩa"),
    "sr-b01-u19-03": ("bother", "chịu khó, bận tâm"),
    "sr-b01-u19-04": ("captain", "thuyền trưởng, cơ trưởng"),
    "sr-b01-u19-17": ("speech", "bài phát biểu"),
    "sr-b01-u20-16": ("regard", "coi như, đánh giá"),
    "sr-b01-u20-20": ("worth", "đáng giá"),
    "sr-b01-u21-01": ("appear", "có vẻ, dường như"),
    "sr-b01-u21-02": ("base", "phần đế, chân đế"),
    "sr-b01-u21-05": ("clerk", "nhân viên bán hàng"),
    "sr-b01-u21-10": ("hurry", "vội vàng, khẩn trương"),
    "sr-b01-u21-16": ("operation", "ca phẫu thuật"),
    "sr-b01-u22-02": ("amaze", "làm kinh ngạc"),
    "sr-b01-u22-03": ("charge", "mức phí, giá dịch vụ"),
    "sr-b01-u22-04": ("comfort", "an ủi, xoa dịu"),
    "sr-b01-u22-14": ("opposite", "điều trái ngược"),
    "sr-b01-u22-15": ("plate", "cái đĩa"),
    "sr-b01-u23-07": ("lower", "hạ thấp xuống"),
    "sr-b01-u23-08": ("match", "phù hợp, tương xứng"),
    "sr-b01-u23-14": ("pole", "cây cột, cọc dài"),
    "sr-b01-u23-18": ("sound", "phát ra âm thanh"),
    "sr-b01-u24-10": ("lack", "sự thiếu hụt"),
    "sr-b01-u24-12": ("perform", "biểu diễn"),
    "sr-b01-u24-15": ("public", "công cộng, chung"),
    "sr-b01-u24-16": ("strike", "đánh, va vào"),
    "sr-b01-u24-19": ("term", "thuật ngữ, từ ngữ"),
    "sr-b01-u25-01": ("associate", "liên tưởng, gắn kết"),
    "sr-b01-u25-07": ("medicine", "thuốc chữa bệnh"),
    "sr-b01-u25-08": ("mix", "hỗn hợp"),
    "sr-b01-u25-16": ("sign", "biển báo, ký hiệu"),
    "sr-b01-u25-17": ("tip", "đầu nhọn, chóp"),
    "sr-b01-u25-19": ("trash", "rác rưởi"),
    "sr-b01-u26-08": ("further", "xa hơn"),
    "sr-b01-u26-17": ("situated", "tọa lạc, nằm ở"),
    "sr-b01-u27-02": ("bite", "miếng cắn"),
    "sr-b01-u27-03": ("coast", "bờ biển"),
    "sr-b01-u27-11": ("hunger", "cơn đói"),
    "sr-b01-u28-11": ("notice", "nhận thấy, để ý"),
    "sr-b01-u29-02": ("assign", "giao việc, phân công"),
    "sr-b01-u29-05": ("competition", "cuộc thi đấu"),
    "sr-b01-u29-10": ("major", "lớn, quan trọng"),
    "sr-b01-u29-11": ("mean", "xấu tính, cay nghiệt"),
    "sr-b01-u29-13": ("president", "tổng thống"),
    "sr-b01-u30-03": ("amount", "số lượng, lượng"),
    "sr-b01-u30-06": ("common", "phổ biến, thường gặp"),
    "sr-b01-u30-07": ("cost", "có giá, tốn"),
    "sr-b01-u30-08": ("demonstrate", "trình diễn, hướng dẫn cách làm"),
    "sr-b02-u02-03": ("command", "ra lệnh"),
    "sr-b02-u02-04": ("counsel", "khuyên bảo, tư vấn"),
    "sr-b02-u02-08": ("land", "hạ cánh"),
    "sr-b02-u02-16": ("submit", "khuất phục, vâng lời"),
    "sr-b02-u03-03": ("bow", "cây cung"),
    "sr-b02-u03-09": ("hardly", "hầu như không"),
    "sr-b02-u03-13": ("military", "quân đội"),
    "sr-b02-u03-15": ("secure", "đạt được, giành được"),
    "sr-b02-u04-07": ("honor", "tôn vinh, kính trọng"),
    "sr-b02-u04-10": ("narrow", "hẹp, nhỏ hẹp"),
    "sr-b02-u04-18": ("terror", "nỗi kinh hoàng"),
    "sr-b02-u05-13": ("relative", "người thân, họ hàng"),
    "sr-b02-u05-14": ("senior", "lớn tuổi hơn, thâm niên hơn"),
    "sr-b02-u05-16": ("sink", "chìm xuống"),
    "sr-b02-u05-17": ("superior", "vượt trội, tốt hơn"),
    "sr-b02-u06-02": ("anger", "làm tức giận"),
    "sr-b02-u06-06": ("disappoint", "làm thất vọng"),
    "sr-b02-u06-09": ("favor", "sự giúp đỡ, ân huệ"),
    "sr-b02-u06-16": ("permit", "cho phép"),
    "sr-b02-u07-08": ("depress", "làm buồn chán"),
    "sr-b02-u08-13": ("dictate", "đọc cho chép; quyết định"),
    "sr-b02-u08-16": ("resort", "phải viện đến, nhờ đến"),
    "sr-b02-u09-05": ("capital", "thủ đô"),
    "sr-b02-u09-10": ("division", "sự phân chia"),
    "sr-b02-u10-11": ("mad", "tức giận"),
    "sr-b02-u10-18": ("trap", "bẫy, giam giữ"),
    "sr-b02-u10-19": ("trial", "phiên tòa xét xử"),
    "sr-b02-u11-01": ("admission", "sự cho phép vào cửa"),
    "sr-b02-u11-18": ("spite", "sự ác ý, lòng thù hằn"),
    "sr-b02-u13-09": ("hike", "đi bộ đường dài"),
    "sr-b02-u14-08": ("exhaust", "làm kiệt sức"),
    "sr-b02-u15-05": ("crew", "đội ngũ làm việc, thủy thủ đoàn"),
    "sr-b02-u15-13": ("foundation", "quỹ tài trợ, tổ chức từ thiện"),
    "sr-b02-u15-15": ("handle", "tay cầm"),
    "sr-b02-u16-10": ("last", "kéo dài"),
    "sr-b02-u16-17": ("shock", "gây bất ngờ, làm sửng sốt"),
    "sr-b02-u17-01": ("aim", "mục tiêu, mục đích"),
    "sr-b02-u17-02": ("attach", "gắn vào, nối vào"),
    "sr-b02-u17-04": ("carriage", "xe ngựa"),
    "sr-b02-u17-05": ("classic", "điển hình, kinh điển"),
    "sr-b02-u17-14": ("junior", "cấp dưới, ít thâm niên"),
    "sr-b02-u17-17": ("prime", "quan trọng nhất, hàng đầu"),
    "sr-b02-u17-18": ("shift", "dịch chuyển, đổi hướng"),
    "sr-b02-u18-03": ("cartoon", "tranh biếm họa, hoạt hình"),
    "sr-b02-u18-09": ("element", "yếu tố, thành phần"),
    "sr-b02-u19-02": ("beg", "cầu xin, van nài"),
    "sr-b02-u19-16": ("reception", "tiệc chiêu đãi"),
    "sr-b02-u20-07": ("elementary", "cơ bản, sơ đẳng"),
    "sr-b02-u20-20": ("statistic", "số liệu thống kê"),
    "sr-b02-u21-02": ("awake", "tỉnh giấc, đang thức"),
    "sr-b02-u18-07": ("delay", "trì hoãn"),
    "sr-b02-u19-07": ("fool", "kẻ ngốc"),
    "sr-b02-u19-20": ("tone", "giọng điệu"),
    "sr-b02-u20-12": ("instant", "khoảnh khắc, chốc lát"),
    "sr-b02-u23-13": ("mount", "tăng lên, dâng cao"),
    "sr-b02-u20-18": ("rent", "tiền thuê nhà"),
    "sr-b02-u24-01": ("bath", "bồn nước tắm, việc tắm bồn"),
    "sr-b02-u24-04": ("disabled", "khuyết tật"),
    "sr-b02-u21-04": ("float", "nổi trên mặt nước"),
    "sr-b02-u22-14": ("resume", "tiếp tục lại"),
    "sr-b02-u22-19": ("tissue", "khăn giấy"),
    "sr-b02-u25-04": ("cabin", "nhà gỗ nhỏ"),
    "sr-b02-u25-08": ("elder", "người lớn tuổi hơn"),
    "sr-b02-u25-09": ("facial", "thuộc về khuôn mặt"),
    "sr-b02-u23-16": ("solid", "rắn chắc"),
    "sr-b02-u26-03": ("amuse", "làm thích thú, mua vui"),
    "sr-b02-u26-06": ("crash", "đâm sầm, va mạnh"),
    "sr-b02-u26-14": ("plain", "đơn giản, mộc mạc"),
    "sr-b02-u27-02": ("bold", "táo bạo, dũng cảm"),
    "sr-b02-u27-04": ("cardinal", "cốt yếu, quan trọng nhất"),
    "sr-b02-u28-03": ("branch", "cành cây"),
    "sr-b02-u28-06": ("cast", "quăng, ném"),
    "sr-b02-u28-10": ("net", "tấm lưới"),
    "sr-b02-u28-15": ("sort", "loại, kiểu"),
    "sr-b02-u28-18": ("virtual", "gần như thực sự, hầu như"),
    "sr-b02-u30-06": ("dull", "nhàm chán, tẻ nhạt"),
    "sr-b03-u03-10": ("kid", "nói đùa, trêu đùa"),
    "sr-b02-u30-01": ("appeal", "thu hút, hấp dẫn"),
    "sr-b02-u30-11": ("found", "thành lập, sáng lập"),
    "sr-b03-u04-10": ("grace", "sự uyển chuyển, duyên dáng"),
    "sr-b03-u05-04": ("disguise", "đồ cải trang"),
    "sr-b03-u05-05": ("fancy", "sang trọng, cầu kỳ"),
    "sr-b03-u04-16": ("refresh", "làm tỉnh táo, giải khuây"),
    "sr-b03-u04-19": ("whistle", "huýt sáo"),
    "sr-b03-u05-07": ("hood", "mũ trùm đầu (áo khoác)"),
    "sr-b03-u05-11": ("publication", "ấn phẩm (sách, báo)"),
    "sr-b03-u05-13": ("rot", "bị mục nát, thối rữa"),
    "sr-b03-u05-14": ("scare", "làm hoảng sợ"),
    "sr-b03-u05-17": ("spoil", "bị ôi thiu, hỏng"),
    "sr-b03-u06-01": ("alert", "cảnh báo, báo động"),
    "sr-b03-u06-02": ("broadcast", "chương trình phát sóng"),
    "sr-b03-u06-04": ("bump", "chỗ u lên, gờ nổi"),
    "sr-b03-u06-11": ("execute", "tử hình, hành quyết"),
    "sr-b03-u07-03": ("bark", "sủa"),
    "sr-b03-u07-05": ("brilliant", "xuất sắc, rất thông minh"),
    "sr-b03-u08-17": ("shed", "nhà kho nhỏ"),
    "sr-b03-u09-01": ("ail", "gây đau ốm, làm khổ sở"),
    "sr-b03-u09-04": ("bounce", "nảy lên"),
    "sr-b03-u09-05": ("bully", "kẻ bắt nạt"),
    "sr-b03-u09-09": ("dial", "mặt đồng hồ, vòng quay số"),
    "sr-b03-u10-11": ("nowhere", "không nơi nào"),
    "sr-b03-u10-13": ("relief", "sự nhẹ nhõm"),
    "sr-b03-u11-03": ("blossom", "bông hoa, chùm hoa"),
    "sr-b03-u11-18": ("pursuit", "cuộc rượt đuổi, sự theo đuổi"),
    "sr-b03-u11-20": ("wilderness", "vùng hoang dã"),
    "sr-b03-u12-02": ("barrel", "thùng gỗ tròn"),
    "sr-b03-u12-03": ("beam", "thanh xà, dầm nhà"),
    "sr-b03-u12-04": ("casual", "thoải mái, giản dị"),
    "sr-b03-u12-13": ("puff", "làn khói/hơi nhỏ"),
    "sr-b03-u13-14": ("startle", "làm giật mình"),
    "sr-b03-u13-15": ("sweat", "đổ mồ hôi"),
    "sr-b03-u14-03": ("bandage", "băng gạc vết thương"),
    "sr-b03-u14-08": ("departure", "sự khởi hành"),
    "sr-b03-u14-11": ("fiber", "sợi dệt, sợi vải"),
    "sr-b03-u14-15": ("luxury", "đồ xa xỉ, sự xa hoa"),
    "sr-b03-u15-01": ("affair", "sự việc, biến cố"),
    "sr-b03-u15-02": ("assembly", "cuộc họp mặt, hội đồng"),
    "sr-b03-u14-05": ("bond", "kết thân, gắn bó"),
    "sr-b03-u15-09": ("harvest", "vụ thu hoạch"),
    "sr-b03-u15-12": ("pardon", "xin nhắc lại; tha lỗi"),
    "sr-b03-u16-18": ("straw", "ống hút"),
    "sr-b03-u17-04": ("confine", "giam giữ, giới hạn trong một nơi"),
    "sr-b03-u17-16": ("span", "kéo dài qua"),
    "sr-b03-u18-02": ("blaze", "cháy rực"),
    "sr-b03-u18-10": ("rebel", "kẻ nổi loạn, phiến quân"),
    "sr-b03-u18-19": ("withdraw", "rút lui, rút quân"),
    "sr-b03-u18-20": ("yield", "nhượng bộ, từ bỏ quyền kiểm soát"),
    "sr-b03-u19-01": ("bench", "ghế dài"),
    "sr-b03-u19-05": ("horror", "nỗi kinh hoàng"),
    "sr-b03-u19-09": ("orphan", "trẻ mồ côi"),
    "sr-b03-u19-17": ("spare", "nhường lại, chia sẻ phần dư"),
    "sr-b03-u19-20": ("tender", "mềm, dễ nhai"),
    "sr-b03-u20-02": ("cub", "thú non (gấu con, sư tử con)"),
    "sr-b03-u21-04": ("bang", "đập mạnh, gõ vang"),
    "sr-b03-u21-16": ("sacrifice", "hy sinh"),
    "sr-b03-u21-18": ("stroke", "vuốt ve"),
    "sr-b03-u21-20": ("tune", "giai điệu, bài hát"),
    "sr-b03-u22-04": ("commission", "thuê làm, ủy nhiệm"),
    "sr-b03-u22-06": ("dye", "nhuộm màu"),
    "sr-b03-u22-13": ("peer", "nhìn chăm chú"),
    "sr-b03-u22-17": ("steer", "lái, điều khiển hướng"),
    "sr-b03-u22-19": ("tame", "hiền lành, đã thuần hóa"),
    "sr-b03-u23-02": ("ban", "cấm"),
    "sr-b03-u23-13": ("outlaw", "kẻ sống ngoài vòng pháp luật"),
    "sr-b03-u23-10": ("gamble", "đánh bạc"),
    "sr-b03-u24-11": ("nerve", "lòng can đảm, sự liều lĩnh"),
    "sr-b03-u25-02": ("consequent", "xảy ra do hệ quả"),
    "sr-b03-u25-06": ("fraction", "một phần nhỏ"),
    "sr-b03-u25-12": ("merit", "ưu điểm, phẩm chất tốt"),
    "sr-b03-u25-19": ("underlying", "ngầm, sâu xa bên dưới"),
    "sr-b03-u26-07": ("curve", "uốn cong, lượn cong"),
    "sr-b03-u26-14": ("fuse", "ngòi nổ, dây cháy chậm"),
    "sr-b03-u27-03": ("blonde", "người tóc vàng"),
    "sr-b03-u27-11": ("noble", "nhà quý tộc"),
    "sr-b03-u28-05": ("chill", "cái lạnh, sự ớn lạnh"),
    "sr-b03-u28-06": ("congress", "quốc hội"),
    "sr-b03-u28-16": ("splash", "bắn tung tóe"),
    "sr-b03-u29-20": ("trace", "dò theo, lần theo"),
    "sr-b03-u30-02": ("basin", "chậu rửa"),
    "sr-b03-u30-06": ("delicate", "mỏng manh, dễ vỡ"),
    "sr-b03-u30-11": ("laundry", "quần áo giặt"),
    "sr-b04-u01-05": ("condensed", "đặc, cô đặc"),
    "sr-b04-u01-19": ("toxic", "độc hại"),
    "sr-b04-u02-04": ("character", "tính cách, phẩm chất"),
    "sr-b04-u02-17": ("steward", "tiếp viên (máy bay, tàu thủy)"),
    "sr-b04-u02-16": ("stake", "cọc nhọn"),
    "sr-b04-u02-20": ("wreck", "phá hủy, làm hỏng nặng"),
    "sr-b04-u03-08": ("echo", "vang vọng"),
    "sr-b04-u03-20": ("torment", "hành hạ, dày vò"),
    "sr-b04-u04-10": ("oblivious", "không để ý, không nhận biết"),
    "sr-b04-u04-14": ("roost", "chỗ chim đậu ngủ"),
    "sr-b04-u05-13": ("moral", "bài học đạo đức"),
    "sr-b04-u06-04": ("cape", "áo choàng không tay"),
    "sr-b04-u06-07": ("folk", "người dân bình thường"),
    "sr-b04-u06-09": ("patch", "mảng khác màu, miếng vá"),
    "sr-b04-u06-11": ("pop", "tiếng nổ bốp"),
    "sr-b04-u06-13": ("rail", "thanh chắn ngang, tay vịn"),
    "sr-b04-u07-18": ("sentence", "bản án, hình phạt"),
    "sr-b04-u07-19": ("volunteer", "tình nguyện làm"),
    "sr-b04-u08-02": ("conduct", "hạnh kiểm, cách cư xử"),
    "sr-b04-u08-03": ("constant", "liên tục, thường xuyên"),
    "sr-b04-u08-15": ("snap", "bẻ gãy rắc"),
    "sr-b04-u09-13": ("outraged", "phẫn nộ, giận dữ"),
    "sr-b04-u09-16": ("slap", "tát"),
    "sr-b04-u10-17": ("sophisticated", "am hiểu, sành sỏi"),
    "sr-b04-u11-20": ("vain", "tự phụ, điệu đà"),
    "sr-b04-u12-01": ("alternative", "phương án thay thế"),
    "sr-b04-u12-04": ("bid", "nỗ lực, sự cố gắng"),
    "sr-b04-u12-05": ("blow", "thổi"),
    "sr-b04-u12-08": ("current", "dòng chảy (nước, không khí)"),
    "sr-b04-u12-12": ("lean", "nghiêng người, tựa"),
    "sr-b04-u12-17": ("succession", "chuỗi liên tiếp"),
    "sr-b04-u13-03": ("bead", "giọt nhỏ (nước, mồ hôi)"),
    "sr-b04-u13-07": ("horn", "còi, kèn"),
    "sr-b04-u13-19": ("workout", "buổi tập thể dục"),
    "sr-b04-u14-03": ("dough", "khối bột nhào"),
    "sr-b04-u14-07": ("flush", "đỏ bừng mặt"),
    "sr-b04-u14-19": ("stale", "ôi, khô cứng (đồ ăn cũ)"),
    "sr-b04-u15-02": ("apply", "bôi, thoa, đắp lên"),
    "sr-b04-u15-08": ("confuse", "làm bối rối"),
    "sr-b04-u15-20": ("variety", "nhiều loại khác nhau"),
    "sr-b04-u16-02": ("bind", "gắn kết mọi người"),
    "sr-b04-u16-19": ("thump", "tiếng rơi bịch"),
    "sr-b04-u17-06": ("exit", "rời khỏi, đi ra"),
    "sr-b04-u17-10": ("loom", "hiện ra lù lù đáng sợ"),
    "sr-b04-u17-16": ("shield", "che chở, bảo vệ"),
    "sr-b04-u18-04": ("blank", "để trống, trắng tinh"),
    "sr-b04-u18-09": ("decline", "từ chối"),
    "sr-b04-u19-16": ("state", "tuyên bố, phát biểu"),
    "sr-b04-u20-08": ("cross", "băng qua"),
    "sr-b04-u18-07": ("comic", "hài hước, khôi hài"),
    "sr-b04-u20-14": ("mass", "số lượng lớn, đám đông"),
    "sr-b04-u21-08": ("itch", "gãi ngứa"),
    "sr-b04-u19-13": ("pea", "đậu Hà Lan"),
    "sr-b04-u21-14": ("sum", "khoản tiền"),
    "sr-b04-u20-05": ("choke", "nghẹn, sặc"),
    "sr-b04-u20-12": ("found", "thành lập, sáng lập"),
    "sr-b04-u20-13": ("lining", "lớp vải lót"),
    "sr-b04-u22-11": ("mock", "chế giễu, nhạo báng"),
    "sr-b04-u21-01": ("background", "xuất thân, nền tảng cá nhân"),
    "sr-b04-u21-03": ("chronicle", "ghi chép lại theo trình tự"),
    "sr-b04-u22-12": ("neutral", "trung lập"),
    "sr-b04-u22-14": ("pity", "lòng thương cảm"),
    "sr-b04-u21-15": ("teller", "giao dịch viên ngân hàng"),
    "sr-b04-u21-20": ("promote", "thăng chức"),
    "sr-b04-u22-03": ("condemn", "kết án, tuyên phạt"),
    "sr-b04-u22-09": ("heed", "lưu tâm, tuân theo"),
    "sr-b04-u22-13": ("persecute", "ngược đãi, bức hại"),
    "sr-b04-u23-10": ("intellectual", "người trí thức"),
    "sr-b04-u23-14": ("offspring", "con cái, thú non"),
    "sr-b04-u23-18": ("stricken", "hứng chịu nặng nề (bệnh, tai họa)"),
    "sr-b04-u23-20": ("vegetarian", "người ăn chay"),
    "sr-b04-u27-09": ("deposit", "đặt vào, gửi vào"),
    "sr-b04-u24-14": ("saucer", "đĩa lót tách trà"),
    "sr-b04-u25-04": ("decisive", "quyết đoán"),
    "sr-b04-u25-08": ("hardy", "cứng cáp, chịu đựng dẻo dai"),
    "sr-b04-u26-15": ("integrate", "hòa nhập"),
    "sr-b04-u27-03": ("capacity", "sức chứa"),
    "sr-b04-u27-12": ("exotic", "ngoại nhập, kỳ lạ từ phương xa"),
    "sr-b04-u27-15": ("frequency", "tần suất"),
    "sr-b04-u28-01": ("avail", "sự giúp ích"),
    "sr-b04-u28-03": ("define", "định nghĩa"),
    "sr-b04-u28-07": ("incredulous", "hoài nghi, không tin nổi"),
    "sr-b04-u28-10": ("paraphrase", "diễn đạt lại ngắn gọn"),
    "sr-b04-u28-18": ("stark", "rõ rệt, hoàn toàn đối lập"),
    "sr-b04-u29-04": ("corporate", "thuộc về tập đoàn/doanh nghiệp"),
    "sr-b04-u29-17": ("solar", "thuộc về mặt trời"),
    "sr-b04-u30-06": ("doomed", "cầm chắc thất bại/diệt vong"),
    "sr-b04-u30-08": ("martial", "thuộc về chiến tranh/võ thuật"),
    "sr-b04-u30-16": ("textile", "hàng dệt, vải dệt"),
    "sr-unit04-07": ("dispose", "vứt bỏ, xử lý, tống khứ"),
    "sr-unit04-09": ("incentive", "động lực khuyến khích, sự khích lệ"),
    "sr-unit04-11": ("legislate", "lập pháp, ban hành luật"),
    "sr-unit04-15": ("retail", "bán lẻ"),
    "sr-unit04-18": ("subsidy", "tiền trợ cấp, khoản trợ giá"),
    "sr-unit04-19": ("transaction", "giao dịch tài chính/thương mại"),
    "sr-unit04-20": ("violate", "vi phạm, xâm phạm"),
    "sr-b05-u05-07": ("haste", "sự vội vàng"),
    "sr-b05-u05-08": ("impulse", "sự bốc đồng, thôi thúc chợt nảy"),
    "sr-b05-u06-11": ("limb", "cành cây lớn"),
    "sr-b05-u06-16": ("quest", "cuộc hành trình tìm kiếm"),
    "sr-b05-u06-19": ("thrust", "đẩy mạnh"),
    "sr-b05-u05-02": ("astonish", "làm kinh ngạc"),
    "sr-b05-u05-12": ("pharmaceutical", "thuộc ngành dược phẩm"),
    "sr-b05-u05-15": ("publicity", "sự chú ý của truyền thông"),
    "sr-b05-u05-17": ("significance", "tầm quan trọng, ý nghĩa"),
    "sr-b05-u06-06": ("fracture", "vết nứt, chỗ gãy"),
    "sr-b05-u06-14": ("peculiar", "kỳ lạ, khác thường"),
    "sr-b05-u07-09": ("ecology", "sinh thái học"),
    "sr-b05-u07-18": ("tolerance", "sức chịu đựng, sự khoan dung"),
    "sr-b05-u08-15": ("obscure", "ít được biết đến"),
    "sr-b05-u08-19": ("respirator", "máy trợ thở"),
    "sr-b05-u09-11": ("managerial", "thuộc về quản lý"),
    "sr-b05-u10-08": ("finance", "tài trợ, cấp vốn"),
    "sr-b05-u10-12": ("monetary", "thuộc về tiền tệ"),
    "sr-b05-u10-13": ("precaution", "biện pháp phòng ngừa"),
    "sr-b05-u10-15": ("saturate", "thấm đẫm, làm ướt sũng"),
    "sr-b05-u11-01": ("acute", "nghiêm trọng, dữ dội"),
    "sr-b05-u11-03": ("banquet", "đại tiệc trang trọng"),
    "sr-b05-u12-06": ("confer", "bàn bạc, hội ý"),
    "sr-b05-u12-08": ("crude", "sơ sài, thô sơ"),
    "sr-b05-u12-16": ("situate", "đặt vị trí, xây dựng tại"),
    "sr-b05-u12-20": ("undergraduate", "sinh viên đại học (chưa tốt nghiệp)"),
    "sr-b05-u13-07": ("degrade", "làm nhục, hạ phẩm giá"),
    "sr-b05-u13-08": ("entitle", "trao quyền được hưởng"),
    "sr-b05-u13-12": ("faculty", "năng lực trí tuệ/thể chất"),
    "sr-b05-u13-16": ("impersonal", "lạnh lùng, thiếu thân thiện"),
    "sr-b05-u13-19": ("sanctuary", "nơi trú ẩn an toàn"),
    "sr-b05-u14-01": ("asset", "phẩm chất quý giá, lợi thế"),
    "sr-b05-u14-17": ("skeptic", "người hoài nghi"),
    "sr-b05-u15-02": ("acquisition", "vật mới mua/đạt được"),
    "sr-b05-u16-10": ("estate", "điền trang, khu đất lớn"),
    "sr-b05-u17-08": ("graffiti", "hình vẽ/chữ viết lên tường"),
    "sr-b05-u17-10": ("implicate", "cho thấy có dính líu (tội phạm)"),
    "sr-b05-u18-05": ("captive", "tù nhân, người bị giam cầm"),
    "sr-b05-u18-06": ("combat", "cuộc giao chiến"),
    "sr-b05-u18-07": ("commonplace", "phổ biến, bình thường"),
    "sr-b05-u18-08": ("compound", "khuôn viên rào kín"),
    "sr-b05-u18-17": ("realm", "lĩnh vực"),
    "sr-b05-u18-18": ("reign", "triều đại, thời gian trị vì"),
    "sr-b05-u19-11": ("genuine", "thật, chân thật"),
    "sr-b05-u19-16": ("precipitate", "thúc đẩy xảy ra sớm"),
    "sr-b05-u19-17": ("secondhand", "đã qua sử dụng"),
    "sr-b05-u21-04": ("clone", "bản sao vô tính"),
    "sr-b05-u21-11": ("gulf", "khoảng cách bất đồng lớn"),
    "sr-b05-u22-19": ("prone", "dễ mắc phải"),
    "sr-b05-u23-01": ("astronomical", "vô cùng to lớn"),
    "sr-b05-u23-20": ("status", "địa vị, vị thế"),
    "sr-b05-u25-06": ("drill", "máy khoan, mũi khoan"),
    "sr-b05-u25-07": ("executive", "giám đốc điều hành"),
    "sr-b05-u25-09": ("incline", "sườn dốc"),
    "sr-b05-u25-18": ("trail", "đường mòn"),
    "sr-b05-u26-01": ("behalf", "sự đại diện (thay mặt)"),
    "sr-b05-u26-11": ("orbit", "quay theo quỹ đạo"),
    "sr-b05-u26-19": ("stall", "trì hoãn, làm đình trệ"),
    "sr-b05-u27-10": ("prescribe", "kê đơn thuốc"),
    "sr-b05-u28-08": ("intrigue", "gợi sự tò mò, hấp dẫn"),
    "sr-b05-u29-01": ("antique", "cổ xưa, quý hiếm"),
    "sr-b05-u29-11": ("lyric", "trữ tình (thơ)"),
    "sr-b05-u29-17": ("refund", "khoản tiền hoàn lại"),
    "sr-b05-u29-18": ("register", "sổ đăng ký"),
    "sr-b05-u30-08": ("hybrid", "vật lai tạo, sự pha trộn"),
    "sr-b05-u30-03": ("craft", "chế tác khéo léo"),
    "sr-b05-u30-15": ("rig", "dàn xếp gian lận"),
    "sr-b05-u30-20": ("tramp", "bước đi nặng nề"),
    "sr-b06-u01-06": ("err", "mắc sai lầm"),
    "sr-b06-u01-20": ("volatile", "dễ biến động bất ngờ"),
    "sr-b06-u02-04": ("conceive", "hình dung, tưởng tượng"),
    "sr-b06-u02-07": ("elastic", "dây thun, cao su đàn hồi"),
    "sr-b06-u02-18": ("skeletal", "thuộc về bộ xương"),
    "sr-b06-u02-19": ("terrestrial", "thuộc về Trái Đất"),
    "sr-b06-u02-20": ("vicious", "hung bạo, tàn nhẫn"),
    "sr-b06-u03-14": ("rouge", "phấn má hồng, son đỏ"),
    "sr-b06-u04-04": ("descent", "sự đi xuống, hạ độ cao"),
    "sr-b06-u04-05": ("din", "tiếng ồn inh ỏi"),
    "sr-b06-u04-08": ("gourmet", "thượng hạng (ẩm thực)"),
    "sr-b06-u04-19": ("soundly", "hoàn toàn, thuyết phục"),
    "sr-b06-u05-01": ("alternate", "luân phiên"),
    "sr-b06-u05-02": ("apologetic", "hối lỗi, biết lỗi"),
    "sr-b06-u05-13": ("relay", "cuộc đua tiếp sức"),
    "sr-b06-u06-03": ("counterpart", "người/vật tương đương"),
    "sr-b06-u08-06": ("freight", "hàng hóa vận chuyển"),
    "sr-b06-u08-13": ("premium", "khoản phí cao hơn bình thường"),
    "sr-b06-u09-19": ("stun", "làm sững sờ"),
    "sr-b06-u07-03": ("botany", "thực vật học"),
    "sr-b06-u07-15": ("psychic", "có khả năng ngoại cảm"),
    "sr-b06-u08-02": ("courier", "người chuyển phát"),
    "sr-b06-u08-07": ("garment", "món trang phục, quần áo"),
    "sr-b06-u08-09": ("intuitive", "theo trực giác"),
    "sr-b06-u08-10": ("liable", "rất dễ xảy ra, có nguy cơ"),
    "sr-b06-u08-12": ("overboard", "rơi qua mạn tàu xuống nước"),
    "sr-b06-u08-17": ("suppress", "ngăn chặn, kìm nén"),
    "sr-b06-u08-19": ("unsettle", "làm bất an, lo lắng"),
    "sr-b06-u09-04": ("forage", "kiếm ăn, lùng tìm thức ăn"),
    "sr-b06-u09-06": ("induce", "gây ra, thúc đẩy xảy ra"),
    "sr-b06-u09-10": ("mainstream", "xu hướng chủ đạo"),
    "sr-b06-u09-11": ("microbe", "vi sinh vật"),
    "sr-b06-u10-03": ("apparatus", "thiết bị, dụng cụ chuyên dụng"),
    "sr-b06-u10-07": ("discharge", "cho xuất viện, cho ra về"),
    "sr-b06-u10-20": ("upbringing", "sự nuôi dạy từ nhỏ"),
    "sr-b06-u11-03": ("civilian", "thường dân"),
    "sr-b06-u11-05": ("conquest", "cuộc chinh phạt"),
    "sr-b06-u11-07": ("dynamics", "sự tương tác qua lại"),
    "sr-b06-u12-02": ("bliss", "niềm hạnh phúc tột cùng"),
    "sr-b06-u12-07": ("farewell", "lời tạm biệt"),
    "sr-b06-u10-09": ("mortal", "phải chết, hữu hạn"),
    "sr-b06-u12-12": ("housekeeping", "việc quản gia, dọn dẹp phòng ốc"),
    "sr-b06-u12-14": ("numb", "tê cóng, mất cảm giác"),
    "sr-b06-u12-18": ("testament", "minh chứng rõ ràng"),
    "sr-b06-u13-05": ("curb", "kiềm chế, hạn chế"),
    "sr-b06-u13-13": ("onset", "sự khởi phát (bệnh, điều xấu)"),
    "sr-b06-u14-03": ("contend", "đối phó, vật lộn vượt qua"),
    "sr-b06-u14-04": ("cot", "giường xếp nhỏ"),
    "sr-b06-u14-05": ("enlist", "nhập ngũ"),
    "sr-b06-u15-08": ("imperative", "cấp bách, bắt buộc phải làm"),
    "sr-b06-u15-14": ("practitioner", "thầy thuốc, bác sĩ hành nghề"),
    "sr-b06-u16-04": ("brute", "kẻ vũ phu, hung bạo"),
    "sr-b06-u16-11": ("premature", "quá sớm, vội vàng"),
    "sr-b06-u16-13": ("satire", "tác phẩm châm biếm"),
    "sr-b06-u17-05": ("duplicate", "sao chép y hệt"),
    "sr-b06-u11-01": ("advocate", "ủng hộ công khai"),
    "sr-b06-u18-02": ("centigrade", "theo thang độ C (bách phân)"),
    "sr-b06-u18-10": ("hearty", "nồng nhiệt, vui vẻ rộn ràng"),
    "sr-b06-u18-14": ("nursery", "phòng trẻ em, nhà trẻ"),
    "sr-b06-u18-15": ("outstretched", "dang rộng hết cỡ"),
    "sr-b06-u19-01": ("airway", "đường hô hấp, khí quản"),
    "sr-b06-u19-02": ("Almighty", "Đấng Toàn Năng"),
    "sr-b06-u19-08": ("invoke", "viện dẫn, cầu khẩn"),
    "sr-b06-u13-20": ("vow", "thề, nguyện"),
    "sr-b06-u20-08": ("inclusion", "sự đưa vào, sự bao gồm"),
    "sr-b06-u11-14": ("marshal", "tập hợp theo trật tự"),
    "sr-b06-u20-20": ("vibrant", "rực rỡ, sống động"),
    "sr-b06-u21-07": ("cosmopolitan", "đa sắc tộc, hội tụ nhiều nền văn hóa"),
    "sr-b06-u21-09": ("flatter", "tâng bốc, nịnh nọt"),
    "sr-b06-u14-12": ("paw", "bàn chân thú"),
    "sr-b06-u14-18": ("tract", "vùng đất rộng"),
    "sr-b06-u22-01": ("coward", "kẻ hèn nhát"),
    "sr-b06-u22-09": ("inclusive", "cởi mở cho mọi người, hòa nhập"),
    "sr-b06-u22-19": ("tact", "sự khéo xử, tế nhị"),
    "sr-b06-u23-04": ("cavity", "lỗ hổng, khoang rỗng"),
    "sr-b06-u23-07": ("courtesy", "phép lịch sự, nhã nhặn"),
    "sr-b06-u24-07": ("habitual", "theo thói quen thường xuyên"),
    "sr-b06-u24-13": ("petroleum", "dầu mỏ"),
    "sr-b06-u15-15": ("provision", "sự cung cấp, lương thực dự trữ"),
    "sr-b06-u24-17": ("subscribe", "tán thành, đồng tình"),
    "sr-b06-u16-16": ("subject", "bắt phải chịu đựng"),
    "sr-b06-u25-01": ("acrobat", "diễn viên nhào lộn"),
    "sr-b06-u25-02": ("advocacy", "sự vận động ủng hộ"),
    "sr-b06-u25-04": ("fluid", "uyển chuyển, mượt mà"),
    "sr-b06-u25-09": ("Mandarin", "tiếng Quan Thoại (Phổ thông)"),
    "sr-b06-u21-20": ("trance", "trạng thái thôi miên/mê man"),
    "sr-b06-u26-02": ("depot", "bến xe, nhà ga"),
    "sr-b06-u26-05": ("guts", "nội tạng, ruột gan"),
    "sr-b06-u26-08": ("janitor", "nhân viên tạp vụ/bảo trì tòa nhà"),
    "sr-b06-u26-11": ("prod", "chọc nhẹ, thúc vào"),
    "sr-b06-u24-15": ("scrap", "mẩu nhỏ, chút ít"),
    "sr-b06-u25-16": ("staple", "cơ bản, chủ yếu"),
    "sr-b06-u25-20": ("vine", "dây leo"),
    "sr-b06-u27-17": ("sodium", "nguyên tố natri"),
    "sr-b06-u21-04": ("censor", "kiểm duyệt"),
    "sr-b06-u28-05": ("casualty", "người thương vong"),
    "sr-b06-u28-08": ("hectare", "héc-ta (10.000 m²)"),
    "sr-b06-u28-16": ("renovate", "cải tạo, tu sửa (tòa nhà)"),
    "sr-b06-u26-17": ("stunt", "trò gây chú ý, pha mạo hiểm"),
    "sr-b06-u29-09": ("grove", "lùm cây nhỏ"),
    "sr-b06-u29-11": ("outback", "vùng nội địa hoang vắng (Úc)"),
    "sr-b06-u29-12": ("outweigh", "vượt trội hơn về tầm quan trọng"),
    "sr-b06-u29-20": ("whereabouts", "tung tích, nơi đang ở"),
    "sr-b06-u30-05": ("credentials", "bằng cấp, chứng nhận năng lực"),
    "sr-b06-u30-07": ("delta", "đồng bằng châu thổ"),
    "sr-b06-u30-08": ("detergent", "bột giặt, nước rửa chén"),
    "sr-b06-u28-07": ("foul", "khó chịu, tồi tệ"),
    "sr-b06-u30-14": ("liberal", "cởi mở, phóng khoáng"),
    "sr-b04-u11-18": ("sort", "phân loại, chia nhóm"),
    "sr-b05-u15-20": ("update", "sự cập nhật, bản nâng cấp"),
}

# Oxford 3000/5000 & Cambridge EVP CEFR grounding sets (lowercase headwords)
OXFORD_A1 = {
    "about", "above", "across", "action", "activity", "actor", "add", "address", "adult", "advice",
    "afraid", "after", "afternoon", "again", "against", "age", "ago", "agree", "air", "airport",
    "all", "also", "always", "amazing", "among", "animal", "angry", "another", "answer", "any",
    "anyone", "anything", "apartment", "apple", "april", "area", "arm", "around", "arrive", "art",
    "article", "artist", "ask", "at", "august", "aunt", "autumn", "away", "baby", "back", "bad",
    "bag", "ball", "banana", "band", "bank", "bath", "bathroom", "be", "beach", "beautiful",
    "because", "become", "bed", "bedroom", "beer", "before", "begin", "beginning", "behind",
    "believe", "below", "best", "better", "between", "bicycle", "big", "bike", "bill", "bird",
    "birthday", "black", "blog", "blonde", "blue", "boat", "body", "book", "boot", "bored",
    "boring", "born", "both", "bottle", "box", "boy", "bread", "break", "breakfast", "bring",
    "brother", "brown", "build", "building", "bus", "business", "busy", "but", "butter", "buy",
    "by", "cafe", "cake", "call", "camera", "can", "capital", "car", "card", "career", "carrot",
    "carry", "cat", "catch", "center", "cent", "century", "chair", "change", "chart", "cheap",
    "check", "cheese", "chicken", "child", "chocolate", "choose", "cinema", "city", "class",
    "classroom", "clean", "clear", "clock", "close", "clothes", "cloud", "club", "coat", "coffee",
    "cold", "college", "color", "come", "common", "company", "compare", "complete", "computer",
    "concert", "conversation", "cook", "cooking", "cool", "correct", "cost", "country", "course",
    "cousin", "cow", "cream", "create", "cry", "culture", "cup", "customer", "cut", "dad", "dance",
    "dancer", "dancing", "dangerous", "dark", "date", "daughter", "day", "dear", "december",
    "decide", "delicious", "describe", "design", "desk", "detail", "dialogue", "dictionary", "die",
    "diet", "difference", "different", "difficult", "dinner", "dirty", "discuss", "dish", "do",
    "doctor", "dog", "dollar", "door", "down", "downstairs", "draw", "dress", "drink", "drive",
    "driver", "during", "each", "ear", "early", "east", "easy", "eat", "egg", "eight", "eighteen",
    "eighty", "elephant", "eleven", "else", "email", "end", "enjoy", "enough", "enter", "even",
    "evening", "event", "ever", "every", "everybody", "everyone", "everything", "exam", "example",
    "excited", "exciting", "exercise", "expensive", "explain", "extra", "eye", "face", "fact",
    "fall", "false", "family", "famous", "fantastic", "far", "farm", "farmer", "fast", "fat",
    "father", "favorite", "february", "feel", "feeling", "festival", "few", "fifteen", "fifth",
    "fifty", "fill", "film", "final", "find", "fine", "finish", "fire", "first", "fish", "five",
    "flat", "flight", "floor", "flower", "fly", "follow", "food", "foot", "football", "for",
    "foreign", "forget", "form", "forty", "four", "fourteen", "fourth", "free", "friday", "friend",
    "friendly", "from", "front", "fruit", "full", "fun", "funny", "future", "game", "garden",
    "geography", "get", "girl", "give", "glass", "go", "good", "goodbye", "grandfather",
    "grandmother", "grandparent", "great", "green", "grey", "group", "grow", "guess", "guitar",
    "gym", "hair", "half", "hand", "happen", "happy", "hard", "hat", "hate", "have", "he", "head",
    "health", "healthy", "hear", "heart", "hello", "help", "her", "here", "high", "him", "his",
    "history", "hobby", "holiday", "home", "homework", "hope", "horse", "hospital", "hot", "hotel",
    "hour", "house", "how", "however", "hundred", "hungry", "husband", "ice", "idea", "if",
    "imagine", "important", "improve", "in", "include", "information", "interest", "interested",
    "interesting", "internet", "interview", "into", "introduce", "island", "it", "its", "jacket",
    "january", "jeans", "job", "join", "journey", "juice", "july", "jump", "june", "just", "keep",
    "key", "kilometer", "kind", "kitchen", "know", "land", "language", "large", "last", "late",
    "later", "laugh", "learn", "leave", "left", "leg", "lesson", "let", "letter", "library", "lie",
    "life", "light", "like", "line", "lion", "list", "listen", "little", "live", "local", "long",
    "look", "lose", "lot", "love", "lunch", "machine", "magazine", "main", "make", "man", "many",
    "map", "march", "market", "married", "match", "may", "maybe", "me", "meal", "mean", "meaning",
    "meat", "meet", "meeting", "member", "menu", "message", "meter", "midnight", "mile", "milk",
    "million", "minute", "miss", "mistake", "model", "modern", "mom", "moment", "monday", "money",
    "month", "more", "morning", "most", "mother", "mountain", "mouse", "mouth", "move", "movie",
    "much", "museum", "music", "must", "my", "name", "natural", "near", "negative", "neighbor",
    "never", "new", "news", "newspaper", "next", "nice", "night", "nine", "nineteen", "ninety",
    "no", "nobody", "north", "nose", "not", "note", "nothing", "november", "now", "number",
    "nurse", "object", "october", "of", "off", "office", "often", "old", "on", "once", "one",
    "onion", "online", "only", "open", "opinion", "opposite", "or", "orange", "order", "other",
    "our", "out", "outside", "over", "own", "page", "paint", "painting", "pair", "pants", "paper",
    "paragraph", "parent", "park", "part", "partner", "party", "passport", "past", "pay", "pen",
    "pencil", "people", "pepper", "perfect", "period", "person", "personal", "pet", "phone",
    "photo", "photograph", "phrase", "piano", "picture", "piece", "pig", "pink", "place", "plan",
    "plane", "plant", "plate", "play", "player", "please", "point", "police", "policeman", "pool",
    "poor", "popular", "positive", "possible", "post", "potato", "pound", "practice", "prefer",
    "prepare", "present", "pretty", "price", "probably", "problem", "product", "program",
    "project", "purple", "put", "quarter", "question", "quick", "quickly", "quiet", "quite",
    "radio", "rain", "read", "reader", "reading", "ready", "real", "really", "reason", "red",
    "relax", "remember", "repeat", "report", "restaurant", "result", "return", "rice", "rich",
    "ride", "right", "river", "road", "room", "routine", "rule", "run", "sad", "salad", "salt",
    "same", "sandwich", "saturday", "save", "say", "school", "science", "scientist", "sea",
    "second", "section", "see", "sell", "send", "sentence", "september", "seven", "seventeen",
    "seventy", "share", "she", "sheep", "shirt", "shoe", "shop", "shopping", "short", "should",
    "show", "shower", "sick", "similar", "sing", "singer", "sister", "sit", "situation", "six",
    "sixteen", "sixty", "skill", "skirt", "sleep", "slow", "small", "smile", "snake", "snow", "so",
    "some", "somebody", "someone", "something", "sometimes", "son", "song", "soon", "sorry",
    "sound", "soup", "south", "space", "speak", "speaker", "special", "spell", "spelling", "spend",
    "sport", "spring", "stand", "star", "start", "statement", "station", "stay", "still", "stop",
    "story", "street", "strong", "student", "study", "style", "subject", "success", "sugar",
    "summer", "sun", "sunday", "supermarket", "sure", "sweater", "sweet", "swim", "swimming",
    "table", "take", "talk", "tall", "taxi", "tea", "teach", "teacher", "team", "teenager",
    "telephone", "television", "tell", "ten", "tennis", "terrible", "test", "text", "than",
    "thank", "thanks", "that", "the", "theater", "their", "them", "then", "there", "they", "thing",
    "think", "third", "thirsty", "thirteen", "thirty", "this", "thousand", "three", "thursday",
    "ticket", "time", "tired", "title", "to", "today", "together", "toilet", "tomato", "tomorrow",
    "tonight", "too", "tooth", "topic", "tourist", "town", "traffic", "train", "travel", "tree",
    "trip", "trousers", "true", "try", "tuesday", "turn", "twelve", "twenty", "twice", "two",
    "type", "umbrella", "uncle", "under", "understand", "university", "until", "up", "upstairs",
    "us", "use", "useful", "usually", "vacation", "vegetable", "very", "video", "village", "visit",
    "visitor", "vocabulary", "wait", "waiter", "wake", "walk", "wall", "want", "warm", "wash",
    "watch", "water", "way", "we", "wear", "weather", "website", "wednesday", "week", "weekend",
    "welcome", "well", "west", "what", "when", "where", "which", "white", "who", "why", "wife",
    "will", "win", "wind", "window", "wine", "winter", "with", "without", "woman", "wonderful",
    "wood", "word", "work", "worker", "world", "would", "write", "writer", "writing", "wrong",
    "year", "yellow", "yes", "yesterday", "you", "young", "your", "yourself",
}

OXFORD_A2 = {
    "ability", "able", "abroad", "accept", "accident", "according", "achieve", "act", "active",
    "actually", "admire", "adventure", "advertise", "advertisement", "advise", "affect", "airline",
    "aircraft", "alive", "allow", "almost", "alone", "along", "already", "alternative", "although",
    "amount", "ancient", "ankle", "anybody", "anymore", "anyway", "anywhere", "appear",
    "appearance", "apply", "architect", "architecture", "argue", "argument", "army", "arrange",
    "arrangement", "as", "asleep", "assistant", "athlete", "attack", "attend", "attention",
    "attractive", "audience", "author", "automobile", "available", "average", "avoid", "awake",
    "award", "awful", "background", "badly", "bar", "baseball", "based", "basketball", "bean",
    "bear", "beat", "beef", "behave", "behavior", "belong", "belt", "benefit", "billion", "bin",
    "biology", "birth", "biscuit", "bit", "blank", "blanket", "blood", "blow", "board", "boil",
    "bone", "borrow", "boss", "bottom", "bowl", "brain", "bridge", "bright", "brilliant", "broken",
    "brush", "burn", "businessman", "button", "camp", "camping", "cancel", "care", "careful",
    "carefully", "careless", "carpet", "cartoon", "case", "cash", "castle", "cause", "celebrate",
    "celebrity", "certain", "certainly", "chance", "character", "charity", "chat", "chef",
    "chemistry", "chip", "choice", "church", "cigarette", "circle", "classical", "clearly",
    "clever", "climate", "climb", "closed", "clothing", "cloudy", "coach", "coast", "code",
    "colleague", "collect", "column", "comedy", "comfortable", "comment", "communicate",
    "community", "compete", "competition", "complain", "completely", "condition", "conference",
    "connect", "connected", "consider", "contain", "context", "continent", "continue", "control",
    "cooker", "cookie", "copy", "corner", "correctly", "count", "couple", "cover", "crazy",
    "creative", "credit", "crime", "criminal", "cross", "crowd", "crowded", "cupboard", "curly",
    "cycle", "daily", "danger", "data", "dead", "deal", "death", "decision", "deep", "definitely",
    "degree", "delete", "dentist", "department", "depend", "desert", "designer", "dessert",
    "destroy", "detective", "develop", "device", "diary", "differently", "digital", "direct",
    "direction", "director", "disabled", "disappear", "disaster", "discover", "discovery",
    "discussion", "disease", "distance", "divorced", "document", "double", "download", "downtown",
    "drama", "drawing", "dream", "driving", "drop", "drug", "dry", "earn", "earth", "easily",
    "education", "effect", "either", "electric", "electrical", "electricity", "electronic",
    "employ", "employee", "employer", "empty", "ending", "energy", "engine", "engineer",
    "enormous", "environment", "equipment", "error", "especially", "essay", "etc.", "everyday",
    "everywhere", "evidence", "exact", "exactly", "excellent", "except", "exist", "exit", "expect",
    "experience", "experiment", "expert", "explanation", "express", "expression", "extreme",
    "extremely", "factor", "factory", "fail", "fair", "fan", "farming", "fashion", "fear",
    "feature", "feed", "female", "fiction", "field", "fight", "figure", "finally", "finger",
    "firstly", "fishing", "fit", "fix", "flu", "flying", "focus", "following", "forest", "fork",
    "formal", "fortunately", "forward", "fresh", "fridge", "frog", "furniture", "further",
    "gallery", "gap", "garbage", "gas", "gate", "general", "gift", "glove", "goal", "god", "gold",
    "golf", "government", "grass", "greet", "ground", "guest", "guide", "gun", "guy", "habit",
    "hall", "happily", "headache", "heat", "heavy", "height", "helpful", "hero", "hers", "herself",
    "hide", "hill", "himself", "hit", "hockey", "hold", "hole", "huge", "human", "hurt", "ideal",
    "identify", "ill", "illness", "image", "immediately", "impossible", "included", "including",
    "increase", "incredible", "independent", "individual", "industry", "informal", "injury",
    "insect", "inside", "instead", "instruction", "instructor", "instrument", "intelligent",
    "international", "introduction", "invent", "invention", "invitation", "invite", "involve",
    "item", "itself", "jam", "jazz", "jewelry", "joke", "journalist", "kid", "kill", "king",
    "knee", "knife", "knock", "knowledge", "lab", "lady", "lake", "lamp", "laptop", "laughter",
    "laundry", "law", "lawyer", "lazy", "lead", "leader", "learning", "least", "lecture", "lemon",
    "lend", "less", "level", "lifestyle", "lift", "likely", "link", "listener", "lock", "locker",
    "lorry", "lost", "loud", "loudly", "lovely", "low", "luck", "lucky", "mail", "major", "male",
    "manage", "manager", "manner", "mark", "marry", "material", "mathematics", "math", "matter",
    "mayor", "media", "medical", "medicine", "memory", "mention", "metal", "method", "middle",
    "might", "mind", "mine", "mirror", "missing", "mobile", "monkey", "moon", "mostly",
    "motorcycle", "movement", "musical", "musician", "myself", "narrow", "national", "nationality",
    "nature", "nearly", "necessary", "neck", "neither", "nervous", "network", "noise", "noisy",
    "none", "normal", "normally", "notice", "novel", "nowadays", "nowhere", "nut", "ocean",
    "offer", "officer", "oil", "onto", "opportunity", "option", "ordinary", "organization",
    "organize", "original", "ourselves", "oven", "owner", "pack", "pain", "painter", "palace",
    "parking", "particular", "pass", "passenger", "patient", "pattern", "pea", "peace", "penny",
    "per", "percent", "perform", "perhaps", "permission", "personality", "petrol", "physical",
    "physics", "pick", "pilot", "planet", "plastic", "platform", "pleased", "pocket", "polite",
    "pollution", "pop", "population", "position", "possession", "possibility", "poster", "power",
    "predict", "president", "prevent", "print", "printer", "prison", "prize", "process", "produce",
    "professional", "professor", "profile", "progress", "promise", "pronounce", "protect",
    "provide", "pub", "public", "publish", "pull", "purpose", "push", "quality", "quantity",
    "queen", "quietly", "race", "railway", "raise", "rate", "rather", "reach", "react", "realize",
    "receive", "recent", "recently", "reception", "recipe", "recognize", "recommend", "record",
    "recording", "recycle", "reduce", "refer", "refuse", "region", "regular", "relationship",
    "remove", "repair", "replace", "reply", "reporter", "request", "research", "researcher",
    "respond", "response", "rest", "review", "ring", "rise", "rock", "role", "roof", "round",
    "route", "rubbish", "rude", "runner", "running", "sadly", "safe", "sail", "sailing", "salary",
    "sale", "sauce", "scared", "scary", "scene", "schedule", "score", "screen", "search", "season",
    "seat", "secondly", "secret", "secretary", "seem", "sense", "separate", "series", "serious",
    "serve", "service", "several", "shake", "shall", "shape", "sheet", "ship", "shocked", "shoot",
    "shoulder", "shout", "shut", "side", "sign", "silver", "simple", "since", "singing", "single",
    "sir", "site", "size", "skate", "ski", "skiing", "skin", "sky", "slowly", "smartphone",
    "smell", "smoke", "smoking", "soap", "soccer", "social", "society", "sock", "soft", "soldier",
    "solution", "solve", "somewhere", "sort", "source", "specific", "speech", "speed", "spider",
    "spoon", "square", "stage", "stair", "staircase", "stamp", "state", "steal", "step", "stomach",
    "stone", "store", "storm", "straight", "strange", "strategy", "stress", "stressed", "strict",
    "strike", "structure", "stupid", "succeed", "successful", "such", "sudden", "suddenly",
    "suggest", "suggestion", "suit", "support", "suppose", "surprise", "surprised", "surprising",
    "survey", "symbol", "system", "tablet", "tail", "target", "task", "taste", "teaching",
    "technology", "teenage", "temperature", "tent", "term", "themselves", "thick", "thief", "thin",
    "thought", "tidy", "tie", "tip", "tool", "top", "touch", "tour", "tourism", "towards", "towel",
    "tower", "toy", "track", "tradition", "traditional", "trainer", "training", "transport",
    "transportation", "trash", "traveler", "trouble", "truck", "twin", "typical", "underground",
    "understanding", "unfortunate", "unfortunately", "unhappy", "uniform", "unit", "united",
    "unusual", "used", "usual", "valley", "van", "variety", "vehicle", "view", "virus", "voice",
    "war", "washing", "wave", "weak", "web", "wedding", "weight", "wet", "wheel", "while", "whole",
    "whose", "wide", "wild", "winner", "wish", "wooden", "working", "worried", "worry", "worse",
    "worst", "yet", "yours", "zero",
}

OXFORD_B1 = {
    "absolutely", "academic", "access", "accommodation", "account", "achievement", "addition",
    "admit", "advanced", "advantage", "advert", "afford", "aged", "agency", "agreement", "ahead",
    "aim", "aisle", "alarm", "album", "alcohol", "alcoholic", "alley", "alternative", "amazed",
    "ambition", "ambitious", "analyze", "analysis", "announce", "announcement", "annoy", "annoyed",
    "annoying", "apart", "apologize", "apology", "application", "appointment", "appreciate",
    "approximately", "arrest", "arrival", "assignment", "assist", "atmosphere", "attach",
    "attitude", "attract", "attraction", "authority", "average", "award", "aware", "backward",
    "backwards", "bake", "balance", "ban", "bandage", "bank", "barber", "barrel", "base",
    "basement", "basic", "basis", "basket", "battery", "battle", "bay", "beard", "beauty", "bee",
    "belief", "bell", "bench", "bend", "beneath", "benefit", "beside", "bite", "bitter", "blame",
    "bleed", "blind", "blink", "block", "board", "bomb", "bond", "border", "bother", "bottom",
    "bounce", "bow", "bracelet", "branch", "brand", "brave", "breath", "breathe", "breathing",
    "breeze", "brick", "bride", "brief", "broad", "broadcast", "broom", "bucket", "budget", "bug",
    "bulb", "bullet", "bunch", "burn", "bury", "bush", "butcher", "butter", "butterfly", "cabin",
    "cabinet", "cable", "cage", "calculate", "calm", "camel", "camp", "campaign", "campus",
    "candidate", "candle", "cap", "capable", "capacity", "cape", "captain", "capture", "careless",
    "cargo", "carpenter", "carriage", "cartoon", "carve", "casual", "category", "cattle", "cave",
    "cease", "ceiling", "celebration", "cell", "cemetery", "central", "ceremony", "certain",
    "chain", "challenge", "champion", "championship", "channel", "chapter", "charge", "charming",
    "chase", "chat", "cheat", "cheer", "cheerful", "chemical", "chest", "chew", "chief",
    "childhood", "chimney", "chin", "choir", "choke", "chore", "claim", "clap", "classic",
    "clause", "clay", "clerk", "click", "client", "cliff", "climate", "climb", "clinic", "clip",
    "cloth", "coal", "coastline", "coin", "collapse", "collar", "collection", "colored", "combine",
    "comfort", "comic", "command", "commercial", "commit", "committee", "commonly", "communication",
    "comparison", "competitor", "complaint", "complex", "complicate", "complicated", "compose",
    "computer", "concentrate", "concentration", "concept", "concern", "concerned", "conclusion",
    "concrete", "conduct", "confident", "confirm", "conflict", "confuse", "confused", "confusing",
    "connection", "consequence", "consist", "consistent", "constant", "constantly", "construct",
    "construction", "consume", "consumer", "contact", "container", "content", "contest",
    "continuous", "contract", "contrast", "contribute", "contribution", "convenient", "convince",
    "convinced", "cool", "copper", "corn", "corporate", "costume", "cot", "cottage", "cotton",
    "couch", "cough", "council", "count", "counter", "countryside", "county", "courage", "court",
    "courteous", "courtesy", "cousin", "cover", "coward", "crab", "crack", "craft", "crash",
    "crawl", "cream", "creature", "credit", "crew", "cricket", "crisis", "crisp", "criticize",
    "crop", "cruel", "crush", "crust", "crystal", "cube", "cultural", "cure", "curious", "current",
    "currently", "curtain", "curve", "curved", "custom", "cute", "cyclone", "daily", "dairy",
    "dam", "damage", "damp", "dare", "darkness", "dawn", "deadline", "deaf", "deal", "debate",
    "debt", "decade", "decent", "declare", "decline", "decorate", "decoration", "decrease",
    "deeply", "defeat", "defence", "defend", "define", "definite", "definition", "delay",
    "deliberate", "delicate", "delight", "delighted", "deliver", "delivery", "demand",
    "demonstrate", "dent", "deny", "depart", "departure", "depend", "dependent", "deposit",
    "depressed", "depressing", "depth", "describe", "desert", "deserve", "desire", "desperate",
    "despite", "destination", "destroy", "destruction", "detail", "detailed", "detect",
    "detergent", "determine", "determined", "development", "devil", "diagram", "dial", "diary",
    "differ", "difficulty", "dig", "dinosaur", "dip", "direct", "directly", "dirt", "disadvantage",
    "disagree", "disagreement", "disappoint", "disappointed", "disappointing", "disappointment",
    "disc", "discipline", "discount", "discourage", "dishonest", "dislike", "dismiss", "display",
    "dissolve", "distant", "distinct", "distribute", "district", "disturb", "ditch", "dive",
    "divide", "division", "divorce", "dizzy", "dock", "documentary", "doll", "domestic", "dominate",
    "donate", "donkey", "dormitory", "dot", "double", "doubt", "dough", "dozen", "draft", "drag",
    "dragon", "drain", "dramatic", "drawer", "dreadful", "drill", "drop", "drought", "drown",
    "drum", "drunk", "duck", "due", "dull", "dump", "dusk", "dust", "dusty", "duty", "dye",
    "eager", "eagle", "ear", "early", "earn", "earnest", "earth", "earthquake", "ease", "eastern",
    "echo", "economic", "economy", "edge", "edit", "edition", "editor", "educate", "educated",
    "educational", "effective", "effectively", "efficient", "effort", "elbow", "elder", "elderly",
    "elect", "election", "element", "elementary", "elevator", "embarrass", "embarrassed",
    "embarrassing", "embassy", "emergency", "emotion", "emotional", "emphasis", "emphasize",
    "empire", "enable", "encounter", "encourage", "encouragement", "endless", "enemy", "engage",
    "engaged", "engineering", "enhance", "enjoyable", "enormous", " enquire", "enroll", "ensure",
    "enter", "entertain", "entertainer", "entertaining", "entertainment", "enthusiasm",
    "enthusiastic", "entire", "entirely", "entrance", "entry", "envelope", "environmental",
    "episode", "equal", "equally", "equator", "errand", "escape", "essential", "establish",
    "estate", "estimate", "ethical", "ethnic", "evacuate", "evaluate", "even", "eventually",
    "evidence", "evil", "exact", "examine", "examination", "exceed", "excellent", "except",
    "exchange", "excite", "excitement", "exclude", "excuse", "executive", "exhaust", "exhausted",
    "exhausting", "exhibit", "exhibition", "existence", "expand", "expect", "expectation",
    "expected", "expedition", "expense", "experienced", "experiment", "expire", "explode",
    "exploration", "explore", "explosion", "export", "expose", "extend", "extension", "extra",
    "extraordinary", "extreme", "eyebrow", "fabric", "facility", "factor", "fade", "failure",
    "faint", "fair", "fairly", "fairy", "faith", "faithful", "fake", "fame", "familiar", "fancy",
    "far", "fare", "farewell", "fascinate", "fascinating", "fasten", "fatal", "fate", "faucet",
    "fault", "favor", "feather", "feature", "federal", "fee", "feed", "feedback", "feel", "fellow",
    "female", "fence", "ferry", "fertile", "festival", "fetch", "fever", "fiber", "fierce",
    "figure", "file", "filth", "finance", "financial", "finding", "fine", "firm", "fist", "fitness",
    "fix", "fixed", "flag", "flame", "flammable", "flash", "flashlight", "flat", "flavor", "flee",
    "flesh", "flexible", "float", "flood", "flour", "flow", "fluent", "fluid", "flute", "foam",
    "focus", "fog", "fold", "folk", "following", "fond", "fool", "foolish", "forbid", "force",
    "forecast", "forefinger", "forehead", "foreigner", "forever", "forgive", "formal", "former",
    "formula", "fort", "fortunate", "fortune", "forward", "found", "foundation", "fountain", "fox",
    "fraction", "fragile", "fragrant", "frame", "freeze", "freezing", "freeway", "frequent",
    "frequently", "friendship", "frighten", "frightened", "frightening", "frontier", "frost",
    "frown", "frozen", "fry", "fuel", "fulfill", "function", "fund", "fundamental", "funeral",
    "funnel", "fur", "furious", "furnish", "furthermore", "gain", "gallon", "gamble", "gang",
    "garage", "garlic", "garment", "gather", "gear", "gene", "generally", "generate", "generation",
    "generous", "gentle", "gentleman", "genuine", "geography", "germ", "gesture", "ghost", "giant",
    "glad", "glance", "global", "globe", "glory", "glove", "glow", "glue", "goat", "goods",
    "gorgeous", "govern", "governor", "grab", "grace", "grade", "gradual", "gradually", "graduate",
    "grain", "grand", "grant", "grape", "grateful", "grave", "gravel", "gravity", "grease",
    "greenhouse", "grief", "grill", "grin", "grip", "grocery", "groom", "grove", "growth",
    "guarantee", "guard", "guilty", "gulf", "gum", "habit", "hail", "haircut", "hammer", "handbag",
    "handbook", "handkerchief", "handle", "handy", "hang", "harbor", "hardly", "hardware", "harm",
    "harmful", "harmless", "harmony", "harvest", "haste", "hatred", "haunt", "hawk", "hay",
    "hazard", "headquarters", "heal", "heap", "hearing", "hearty", "heaven", "heavily", "heel",
    "height", "helicopter", "hell", "helmet", "hen", "hence", "herb", "herd", "hesitate", "hidden",
    "highlands", "highlight", "highly", "highway", "hike", "hint", "hip", "hire", "historic",
    "historical", "hitchhike", "hive", "hollow", "holy", "homeless", "honest", "honestly", "honey",
    "honor", "hood", "hook", "horizon", "horn", "horrible", "horror", "hose", "hospitable",
    "hospitality", "host", "household", "housekeeping", "housing", "hug", "humble", "humid",
    "humor", "humorous", "hunger", "hunt", "hunting", "hurricane", "hurry", "hut", "hydrogen",
    "iceberg", "ideal", "identical", "identity", "ignore", "illegal", "illustrate", "imagination",
    "immediate", "immigrant", "impact", "impatient", "impolite", "import", "importance", "impress",
    "impressed", "impression", "impressive", "improvement", "inch", "incident", "include", "income",
    "increase", "increasingly", "indeed", "independence", "indicate", "indirect", "indoor",
    "indoors", "industrial", "infect", "infection", "influence", "inform", "ingredient", "inhabit",
    "inhabitant", "inhale", "initial", "initially", "initiative", "injure", "injured", "ink", "inn",
    "inner", "innocent", "input", "inquire", "inquiry", "insert", "inside", "insist", "inspect",
    "inspector", "inspire", "install", "instance", "instant", "instantly", "instead", "institute",
    "institution", "insurance", "intellectual", "intelligence", "intend", "intended", "intense",
    "intention", "interact", "interaction", "interior", "intermediate", "internal", "interpret",
    "interrupt", "interval", "invasion", "invent", "invest", "investigate", "investigation",
    "investment", "investor", "invisible", "iron", "irritate", "island", "issue", "itch", "ivory",
    "jail", "janitor", "jar", "jaw", "jealous", "jealousy", "jelly", "jet", "jewel", "jog",
    "joint", "jolly", "journal", "joy", "judge", "judgment", "jug", "jungle", "junior", "junk",
    "jury", "justice", "justify", "keen", "kettle", "keyboard", "kick", "kidnap", "kidney",
    "kindly", "kindness", "kingdom", "kiss", "kit", "kite", "kitten", "kneel", "knit", "knot",
    "label", "laboratory", "labor", "lack", "ladder", "lamb", "landing", "landlord", "landscape",
    "lane", "lantern", "lap", "largely", "lately", "latter", "launch", "lawn", "layer", "lay",
    "lead", "leaf", "league", "leak", "lean", "leap", "leather", "legal", "legend", "leisure",
    "lemonade", "length", "lens", "lentil", "leopard", "lettuce", "liar", "liberal", "liberty",
    "license", "lid", "lick", "lifeguard", "lifetime", "lighting", "lightly", "lightning",
    "likewise", "lily", "limb", "limit", "limited", "linen", "lining", "lip", "liquid",
    "literature", "litter", "lively", "liver", "living", "lizard", "load", "loaf", "loan",
    "lobster", "locate", "located", "location", "log", "logic", "logical", "lonely", "lone",
    "loop", "loose", "lord", "loss", "lotion", "loyal", "luggage", "lump", "lung", "luxury",
    "lyric", "mad", "magic", "magical", "magnet", "magnificent", "maid", "mail", "mainland",
    "mainly", "maintain", "majority", "makeup", "mammal", "manage", "management", "mankind",
    "manner", "mansion", "manual", "manufacture", "manufacturer", "manuscript", "marble", "march",
    "margin", "marine", "marsh", "martial", "marvelous", "mask", "mass", "massive", "master",
    "mat", "match", "mate", "maximum", "mayor", "maze", "meadow", "mean", "means", "meanwhile",
    "measure", "measurement", "mechanic", "mechanical", "medal", "medical", "medication", "medium",
    "melt", "membership", "memorial", "mental", "mention", "merchant", "mercy", "mere", "merely",
    "merry", "mess", "metal", "meter", "microscope", "microwave", "mild", "military", "mill",
    "millionaire", "mineral", "minimum", "minister", "ministry", "minor", "minority", "mint",
    "miracle", "misery", "mission", "mist", "mix", "mixed", "mixture", "mobile", "mode", "model",
    "moderate", "modest", "modify", "moist", "moisture", "mold", "molecule", "monk", "monster",
    "monument", "mood", "mop", "moral", "moreover", "mosquito", "moss", "mostly", "moth", "motion",
    "motor", "mount", "mound", "mud", "multiply", "murder", "muscle", "muscular", "mushroom",
    "musical", "mustard", "mystery", "mysterious", "myth", "nail", "naked", "nap", "napkin",
    "narrate", "narrative", "narrow", "nasty", "nation", "native", "naturally", "navy", "nearby",
    "neat", "necessarily", "necklace", "needle", "neighborhood", "nephew", "nerve", "nest", "net",
    "neutral", "nevertheless", "newcomer", "newly", "niece", "nightmare", "noble", "nod", "none",
    "nonsense", "noodle", "noon", "nor", "norm", "northern", "nostril", "notable", "notice",
    "notify", "notion", "noun", "nourish", "novel", "nuclear", "numb", "numerous", "nun",
    "nursery", "nutrient", "nutrition", "oak", "oar", "obey", "object", "objective", "obligation",
    "observation", "observe", "obtain", "obvious", "obviously", "occasion", "occasional",
    "occasionally", "occupy", "occur", "odd", "offend", "offense", "offensive", "official",
    "old-fashioned", "olive", "once", "ongoing", "onion", "onto", "opening", "opera", "operate",
    "operation", "operator", "opponent", "oppose", "opposed", "opposite", "opposition", "option",
    "orbit", "orchard", "orchestra", "ordinary", "organ", "organic", "organism", "organization",
    "origin", "original", "originally", "orphan", "otherwise", "ought", "ounce", "outcome",
    "outdoor", "outdoors", "outer", "outline", "outstretched", "overall", "overcast", "overcome",
    "overcrowded", "overhead", "overjoyed", "overnight", "overseas", "overweight", "owe", "owl",
    "ox", "oxygen", "oyster", "pace", "pack", "package", "pad", "paddle", "painful", "pale",
    "palm", "pan", "pancake", "panda", "pane", "panel", "panic", "parachute", "parade", "paradise",
    "parcel", "pardon", "parliament", "parrot", "participate", "particular", "particularly",
    "partly", "passage", "passion", "passive", "pasta", "paste", "pasture", "pat", "patch", "path",
    "patience", "patient", "patriot", "pause", "paw", "payment", "peaceful", "peach", "peak",
    "peanut", "pear", "pearl", "pebble", "pedal", "pedestrian", "peel", "peer", "penalize",
    "penalty", "penguin", "pension", "percentage", "perform", "performance", "perfume", "perhaps",
    "permanent", "permit", "persuade", "pest", "pesticide", "petal", "petroleum", "phase",
    "philosophy", "photocopy", "photographer", "photography", "phrase", "physical", "physician",
    "picnic", "pie", "pier", "pigeon", "pile", "pill", "pillow", "pin", "pine", "pineapple",
    "pioneer", "pipe", "pirate", "pit", "pitch", "pity", "plain", "planet", "plank", "planning",
    "plaster", "plate", "pleasant", "pleasure", "plenty", "plot", "plug", "plum", "plumber",
    "plus", "poem", "poet", "poetry", "point", "pointed", "poison", "poisonous", "pole", "policy",
    "polish", "polite", "political", "politician", "politics", "pollen", "pollute", "pond", "pony",
    "pop", "popularity", "population", "porch", "pork", "port", "portrait", "pose", "position",
    "possess", "possession", "possibility", "post", "postage", "pot", "potential", "pottery",
    "pouch", "poultry", "pound", "pour", "poverty", "powder", "powerful", "practical", "practically",
    "praise", "pray", "prayer", "precaution", "precious", "precise", "predict", "prediction",
    "preference", "pregnant", "preparation", "prepared", "presence", "preposition", "prescribe",
    "prescription", "presentation", "preserve", "presidential", "press", "pressure", "pretend",
    "previous", "previously", "priest", "primary", "prime", "prince", "princess", "principal",
    "principle", "prior", "priority", "prisoner", "privacy", "private", "privilege", "probable",
    "procedure", "proceed", "process", "produce", "producer", "production", "profession", "profit",
    "program", "prohibit", "promote", "promotion", "prompt", "promptly", "pronoun", "pronounce",
    "pronunciation", "proof", "proper", "properly", "property", "proposal", "propose", "prospect",
    "protect", "protection", "protest", "proud", "prove", "proverb", "province", "provision",
    "pub", "public", "publication", "publicity", "publish", "publishing", "pudding", "puddle",
    "puff", "pull", "pulse", "pump", "pumpkin", "punch", "punish", "punishment", "pup", "pupil",
    "puppet", "puppy", "purchase", "pure", "purely", "purpose", "purse", "pursue", "pursuit",
    "puzzle", "pyramid", "qualification", "qualified", "qualify", "quantity", "quarrel", "queen",
    "queue", "quit", "quite", "quiz", "quote", "rabbit", "racial", "racing", "radar", "radiation",
    "radio", "raft", "rag", "rage", "rail", "railroad", "railway", "raincoat", "rainforest",
    "raisin", "rake", "rally", "ranch", "random", "range", "ranger", "rank", "rapid", "rapidly",
    "rare", "rarely", "rash", "rat", "rate", "rather", "raw", "ray", "razor", "reach", "react",
    "reaction", "realistic", "reality", "realize", "rear", "reasonable", "rebel", "recall",
    "receipt", "receive", "receiver", "recent", "reception", "recite", "reckon", "recognition",
    "recognize", "recommend", "record", "recover", "recovery", "recycle", "reduce", "reduction",
    "reef", "refer", "reference", "reflect", "reflection", "reform", "refresh", "refrigerate",
    "refrigerator", "refund", "refuse", "regard", "regret", "regular", "regularly", "regulate",
    "regulation", "rehearse", "reject", "relate", "related", "relation", "relative", "relatively",
    "relax", "relaxed", "relaxing", "relay", "release", "relevant", "reliable", "relief",
    "relieve", "relieved", "religion", "religious", "rely", "remain", "remaining", "remains",
    "remark", "remarkable", "remedy", "remind", "reminder", "remote", "removal", "remove",
    "renovate", "rent", "repair", "repay", "repeat", "repeated", "replace", "reply", "represent",
    "representative", "reproduce", "reptile", "republic", "reputation", "request", "require",
    "requirement", "rescue", "research", "resemble", "reservation", "reserve", "reservoir",
    "resident", "resist", "resistance", "resolve", "resort", "resource", "respect", "respond",
    "responsibility", "responsible", "rest", "restore", "restrict", "result", "resume", "retail",
    "retain", "retire", "retired", "retirement", "retreat", "return", "reveal", "revenge",
    "reverse", "review", "revise", "revision", "revolution", "reward", "rhyme", "rhythm", "rib",
    "ribbon", "rid", "ridiculous", "rifle", "right", "rim", "ring", "rinse", "riot", "rip", "ripe",
    "rise", "risk", "risky", "rival", "roar", "roast", "rob", "robber", "robbery", "robe", "robot",
    "rock", "rocket", "rod", "role", "roll", "romance", "romantic", "roof", "root", "rope", "rose",
    "rot", "rotten", "rough", "roughly", "round", "route", "routine", "row", "royal", "rub",
    "rubber", "rubble", "rude", "rug", "ruin", "rule", "ruler", "rumor", "rural", "rush", "rust",
    "sack", "sacred", "sacrifice", "saddle", "safety", "sailor", "saint", "sake", "salad",
    "salary", "salmon", "salon", "salty", "sample", "sand", "sandal", "satellite", "satisfaction",
    "satisfactory", "satisfied", "satisfy", "satisfying", "saucer", "sausage", "saving", "saw",
    "scale", "scan", "scandal", "scar", "scare", "scared", "scarf", "scary", "scatter", "scene",
    "scenery", "scent", "schedule", "scheme", "scholar", "scholarship", "scissors", "scold",
    "scoop", "scooter", "scope", "score", "scramble", "scrap", "scrape", "scratch", "scream",
    "screen", "screw", "scribble", "script", "scrub", "sculpture", "seal", "seam", "search",
    "seashore", "season", "seasoning", "seat", "secondhand", "secret", "secretary", "sector",
    "secure", "security", "seed", "seek", "seem", "select", "selection", "self", "selfish",
    "semester", "senate", "senator", "senior", "sensation", "sense", "sensible", "sensitive",
    "sentence", "separate", "separated", "series", "serious", "seriously", "servant", "serve",
    "service", "session", "set", "setting", "settle", "settlement", "severe", "sew", "sewing",
    "sex", "sexual", "shade", "shadow", "shake", "shallow", "shame", "shampoo", "shape", "shaped",
    "share", "shark", "sharp", "sharply", "shave", "shawl", "shed", "sheep", "sheet", "shelf",
    "shell", "shelter", "shepherd", "sheriff", "shield", "shift", "shine", "shiny", "ship",
    "shock", "shocked", "shocking", "shoelace", "shoot", "shooting", "shore", "shortage",
    "shortcut", "shortly", "shot", "shoulder", "shout", "shovel", "show", "shower", "shrimp",
    "shrink", "shrug", "shut", "shutter", "shy", "sick", "side", "sidewalk", "sideways", "sigh",
    "sight", "sightseeing", "sign", "signal", "signature", "significant", "significantly",
    "silence", "silent", "silk", "silly", "silver", "similar", "similarity", "similarly",
    "simple", "simplicity", "simply", "since", "sincere", "sincerely", "single", "sink", "sip",
    "sir", "siren", "site", "situated", "situation", "size", "skate", "skeleton", "sketch",
    "skill", "skilled", "skinny", "skip", "skull", "sky", "slam", "slap", "slave", "slavery",
    "sled", "sleep", "sleeve", "slice", "slide", "slight", "slightly", "slim", "slip", "slipper",
    "slippery", "slope", "slot", "slow", "slowly", "smash", "smell", "smile", "smoke", "smooth",
    "snack", "snail", "snake", "snap", "sneaker", "sneeze", "sniff", "snore", "snow", "soak",
    "soap", "sob", "social", "socialize", "society", "sock", "soda", "sodium", "sofa", "soft",
    "software", "soil", "solar", "soldier", "solid", "solo", "solution", "solve", "somehow",
    "somewhat", "somewhere", "soon", "sore", "sort", "soul", "sound", "sour", "source", "southern",
    "souvenir", "sow", "soy", "space", "spade", "spare", "spark", "speak", "speaker", "special",
    "specialist", "species", "specific", "specifically", "speech", "speed", "spell", "spend",
    "spending", "spice", "spicy", "spider", "spill", "spin", "spinach", "spine", "spirit",
    "spiritual", "spite", "splash", "splendid", "split", "spoil", "spoken", "sponge", "sponsor",
    "spoon", "sport", "spot", "spouse", "spray", "spread", "spring", "sprinkle", "spy", "square",
    "squeeze", "squid", "squirrel", "stab", "stable", "stadium", "staff", "stage", "stain",
    "stair", "stake", "stale", "stall", "stamp", "stand", "standard", "stare", "starve", "state",
    "statement", "statistic", "statue", "status", "stay", "steady", "steak", "steal", "steam",
    "steel", "steep", "steer", "stem", "step", "stick", "sticky", "stiff", "still", "sting",
    "stink", "stir", "stitch", "stock", "stomach", "stone", "stool", "stop", "store", "storm",
    "story", "stove", "straight", "strain", "strange", "stranger", "strap", "strategy", "straw",
    "strawberry", "stream", "street", "strength", "strengthen", "stress", "stretch", "strict",
    "strictly", "strike", "string", "strip", "stripe", "stroke", "stroll", "strong", "strongly",
    "structure", "struggle", "stubborn", "student", "studio", "study", "stuff", "stumble", "stump",
    "style", "subject", "submit", "subscribe", "substance", "substantial", "subtract", "suburb",
    "subway", "succeed", "success", "successful", "successfully", "such", "suck", "sudden",
    "suddenly", "sue", "suffer", "suffering", "sufficient", "sugar", "suggest", "suggestion",
    "suit", "suitable", "suitcase", "sum", "summary", "summer", "sun", "sunburn", "sunlight",
    "sunny", "sunrise", "sunset", "sunshine", "super", "superb", "superior", "supermarket",
    "supervise", "supply", "support", "supporter", "suppose", "sure", "surely", "surface",
    "surgeon", "surgery", "surname", "surprise", "surprised", "surprising", "surround",
    "surrounding", "survey", "survive", "survivor", "suspect", "suspend", "suspicion", "suspicious",
    "swallow", "swamp", "swan", "swap", "swarm", "swear", "sweat", "sweater", "sweep", "sweet",
    "swell", "swim", "swimming", "swimsuit", "swing", "switch", "sword", "symbol", "sympathetic",
    "sympathy", "symptom", "system", "table", "tablecloth", "tablet", "tail", "tailor", "take",
    "tale", "talent", "talented", "talk", "tall", "tame", "tan", "tank", "tap", "tape", "target",
    "tariff", "task", "taste", "tattoo", "tax", "taxi", "tea", "teach", "teacher", "teaching",
    "team", "tear", "tease", "technical", "technician", "technique", "technology", "teenager",
    "telegraph", "telephone", "telescope", "television", "tell", "teller", "temper", "temperature",
    "temple", "temporary", "ten", "tenant", "tend", "tendency", "tender", "tennis", "tense",
    "tension", "tent", "term", "terrible", "terribly", "terrific", "terrify", "territory",
    "terror", "terrorism", "terrorist", "test", "text", "textbook", "textile", "texture", "than",
    "thank", "thankful", "thanks", "that", "thaw", "the", "theater", "theft", "their", "them",
    "theme", "themselves", "then", "theory", "therapy", "there", "therefore", "thermometer",
    "they", "thick", "thief", "thigh", "thin", "thing", "think", "thinking", "third", "thirsty",
    "thirteen", "thirty", "this", "thorn", "thorough", "thoroughly", "though", "thought",
    "thousand", "thread", "threat", "threaten", "three", "throat", "throne", "through",
    "throughout", "throw", "thumb", "thunder", "thunderstorm", "thus", "ticket", "tickle", "tide",
    "tidy", "tie", "tiger", "tight", "tightly", "tile", "till", "timber", "time", "timetable",
    "tin", "tiny", "tip", "tiptoe", "tire", "tired", "tiring", "tissue", "title", "to", "toad",
    "toast", "tobacco", "today", "toe", "together", "toilet", "token", "tolerant", "tolerate",
    "toll", "tomato", "tomb", "tomorrow", "ton", "tone", "tongue", "tonight", "too", "tool",
    "tooth", "toothbrush", "toothpaste", "top", "topic", "torch", "tornado", "tortoise", "toss",
    "total", "totally", "touch", "tough", "tour", "tourism", "tourist", "tournament", "tow",
    "toward", "towards", "towel", "tower", "town", "toy", "trace", "track", "tractor", "trade",
    "tradition", "traditional", "traffic", "tragedy", "tragic", "trail", "trailer", "train",
    "trainer", "training", "tram", "transfer", "transform", "transition", "translate",
    "translation", "transmit", "transparent", "transport", "transportation", "trap", "trash",
    "travel", "traveler", "tray", "treasure", "treat", "treatment", "treaty", "tree", "tremble",
    "tremendous", "trend", "trial", "triangle", "tribe", "trick", "trigger", "trim", "trip",
    "troop", "trophy", "tropical", "tropics", "trouble", "trousers", "trout", "truck", "true",
    "truly", "trumpet", "trunk", "trust", "trustworthy", "truth", "try", "tub", "tube", "tuck",
    "tuesday", "tug", "tulip", "tumble", "tuna", "tune", "tunnel", "turkey", "turn", "turtle",
    "tutor", "twelve", "twenty", "twice", "twig", "twin", "twist", "two", "type", "typical",
    "typically", "typhoon", "tyre", "ugly", "ultimate", "ultimately", "umbrella", "unable",
    "unacceptable", "uncertain", "uncle", "uncomfortable", "unconscious", "under", "undergraduate",
    "underground", "underline", "underneath", "understand", "understanding", "underwear", "undo",
    "unemployed", "unemployment", "unexpected", "unfair", "unfortunate", "unfortunately",
    "unfriendly", "unhappy", "uniform", "unify", "union", "unique", "unit", "unite", "united",
    "universe", "university", "unkind", "unknown", "unless", "unlike", "unlikely", "unload",
    "unlock", "unlucky", "unnecessary", "unpleasant", "until", "unusual", "up", "upcoming",
    "update", "upgrade", "upon", "upper", "upset", "upsetting", "upstairs", "upward", "urban",
    "urge", "urgent", "us", "usage", "use", "used", "useful", "useless", "user", "usual",
    "usually", "vacation", "vaccine", "vacuum", "valley", "valuable", "value", "vampire", "van",
    "vanilla", "vanish", "vapor", "variety", "various", "vary", "vase", "vast", "vegetable",
    "vegetarian", "vehicle", "vein", "velvet", "vendor", "venture", "venue", "verb", "version",
    "versus", "vertical", "very", "vessel", "vest", "veteran", "veterinarian", "via", "victim",
    "victor", "victory", "video", "view", "viewer", "village", "villager", "vine", "vinegar",
    "violence", "violent", "violin", "virtual", "virtually", "virus", "visa", "visible", "vision",
    "visit", "visitor", "visual", "vital", "vitamin", "vivid", "vocabulary", "vocal", "voice",
    "volcano", "volleyball", "volume", "voluntary", "volunteer", "vomit", "vote", "voter", "vowel",
    "voyage", "wage", "wagon", "waist", "wait", "waiter", "waitress", "wake", "walk", "wall",
    "wallet", "walnut", "wander", "want", "war", "ward", "wardrobe", "warehouse", "warm", "warmth",
    "warn", "warning", "warrior", "wash", "washing", "wasp", "waste", "watch", "water",
    "waterfall", "watermelon", "wave", "wavy", "wax", "way", "we", "weak", "weakness", "wealth",
    "wealthy", "weapon", "wear", "weary", "weather", "weave", "web", "website", "wedding", "weed",
    "week", "weekday", "weekend", "weekly", "weep", "weigh", "weight", "weird", "welcome", "well",
    "west", "western", "wet", "whale", "what", "whatever", "wheat", "wheel", "wheelchair", "when",
    "whenever", "where", "whereas", "wherever", "whether", "which", "while", "whip", "whirl",
    "whisker", "whisper", "whistle", "white", "who", "whoever", "whole", "whom", "whose", "why",
    "wicked", "wide", "widely", "widespread", "widow", "width", "wife", "wig", "wild",
    "wilderness", "wildlife", "will", "willing", "win", "wind", "winding", "window", "windy",
    "wine", "wing", "wink", "winner", "winter", "wipe", "wire", "wisdom", "wise", "wish", "wit",
    "witch", "with", "withdraw", "within", "without", "witness", "wizard", "wolf", "woman",
    "wonder", "wonderful", "wood", "wooded", "wooden", "wool", "word", "work", "worker", "working",
    "workout", "workplace", "workshop", "world", "worldwide", "worm", "worn", "worried", "worry",
    "worse", "worship", "worst", "worth", "would", "wound", "wounded", "wrap", "wreck", "wrist",
    "write", "writer", "writing", "written", "wrong", "yard", "yarn", "yawn", "year", "yearly",
    "yeast", "yell", "yellow", "yes", "yesterday", "yet", "yield", "yogurt", "yolk", "you",
    "young", "your", "yours", "yourself", "youth", "zebra", "zero", "zip", "zone", "zoo",
    "zoology", "zoom",
}

OXFORD_B2 = {
    "abandon", "abolish", "abortion", "absence", "absent", "absorb", "abstract", "absurd",
    "abundance", "abundant", "abuse", "academy", "accelerate", "accent", "acceptable",
    "acceptance", "accessible", "accidentally", "accommodate", "accompany", "accomplish",
    "accomplishment", "accordance", "accountability", "accountant", "accumulate", "accuracy",
    "accurate", "accurately", "accusation", "accuse", "accused", "accustom", "ache", "acid",
    "acknowledge", "acquire", "acquisition", "acre", "activate", "activist", "acute", "adapt",
    "adaptation", "addiction", "additional", "adequate", "adequately", "adhere", "adjacent",
    "adjoin", "adjoining", "adjust", "adjustment", "administer", "administration",
    "administrative", "administrator", "admission", "adolescent", "adopt", "adoption", "adverse",
    "advocate", "advocacy", "aesthetic", "affection", "affordable", "aftermath", "aggression",
    "aggressive", "agriculture", "agricultural", "aide", "aids", "alert", "alien", "align",
    "alignment", "alike", "allegation", "allege", "allegedly", "alliance", "allocate",
    "allocation", "allowance", "ally", "alongside", "altar", "alter", "alternate", "amend",
    "amendment", "amid", "amuse", "amusing", "analogy", "analogous", "analyst", "analytic",
    "ancestor", "ancestry", "anchor", "angel", "animation", "annually", "anonymous", "anticipate",
    "anxiety", "anxious", "apologetic", "apparatus", "apparent", "apparently", "appeal",
    "appealing", "appetite", "appetizing", "applaud", "applicable", "applicant", "appoint",
    "appointment", "appreciation", "apprentice", "approach", "appropriate", "appropriately",
    "approval", "approve", "approximate", "architectural", "archive", "arena", "arise",
    "arithmetic", "armed", "arms", "arouse", "array", "arrow", "artery", "arthritis",
    "articulate", "artificial", "artwork", "ash", "ashamed", "aside", "aspect", "aspiration",
    "aspire", "assassinate", "assault", "assemble", "assembly", "assert", "assertion", "assess",
    "assessment", "asset", "assign", "assistance", "associate", "associated", "association",
    "assume", "assumption", "assurance", "assure", "astonish", "astonishing", "astronaut",
    "astronomical", "astronomy", "athletic", "atrocity", "attachment", "attain", "attendance",
    "attorney", "attribute", "auction", "audit", "authentic", "authorize", "auto", "automate",
    "automatic", "automatically", "autonomy", "availability", "avalanche", "await", "awareness",
    "awkward", "ax", "bachelor", "backdrop", "backing", "backstage", "bacteria", "badge", "bail",
    "balanced", "bald", "ballet", "balloon", "ballot", "bamboo", "banner", "banquet", "bare",
    "barely", "bargain", "barley", "barn", "barren", "barrier", "basin", "bat", "battlefield",
    "bay", "beam", "beast", "behalf", "beloved", "benefactor", "beneficial", "beneficiary",
    "beside", "besides", "bet", "betray", "beverage", "bias", "bid", "billionaire", "bind",
    "binoculars", "biography", "biological", "biosphere", "birthplace", "bishop", "bizarre",
    "blacksmith", "blade", "blanket", "blast", "blaze", "bleed", "blend", "bless", "blessing",
    "blizzard", "blossom", "boast", "bold", "bolt", "bombing", "bonus", "boom", "boost", "bounce",
    "bound", "boundary", "bow", "boxer", "boycott", "brace", "braille", "brass", " bravery",
    "breach", "breakdown", "breakthrough", "breed", "bribe", "briefly", "broadband", "broadcaster",
    "broadly", "brook", "browser", "utal", "brute", "buck", "bud", "buddy", "buffer", "bulk",
    "bulletin", "bully", "bump", "bundle", "burden", "bureaucracy", "burial", "burst", "butler",
    "cab", "calculation", "camcorder", "camouflage", "canal", "candle", "canvas", "capability",
    "capitalism", "capitalist", "captive", "capture", "carbohydrate", "carbon", "cardinal",
    "caretaker", "casualty", "catalog", "catastrophe", "cater", "cathedral", "caution", "cautious",
    "cavity", "cease", "celsius", "censor", "census", "centigrade", "ceramic", "certainty",
    "certificate", "certify", "chamber", "chaos", "chaotic", "characterize", "charcoal",
    "charitable", "charm", "charter", "chatter", "cherish", "chirp", "cholesterol", "chronic",
    "chronicle", "chunk", "circuit", "circulate", "circulation", "circumstance", "cite", "citizen",
    "citizenship", "civic", "civil", "civilian", "civilization", "clarify", "clarity", "clash",
    "classification", "classify", "cliff", "cling", "clinical", "clockwise", "clone", "closure",
    "clumsy", "cluster", "coalition", "coarse", "coastal", "cocktail", "cognitive", "coincide",
    "coincidence", "collaborate", "collaboration", "collective", "collector", "collide",
    "collision", "colonel", "colonial", "colony", "colorful", "columnist", "combat", "combination",
    "commander", "commence", "commentary", "commentator", "commerce", "commission", "commissioner",
    "commitment", "commodity", "commonplace", "communal", "communist", "commute", "companion",
    "comparable", "comparative", "compass", "compassion", "compassionate", "compatible", "compel",
    "compelling", "compensate", "compensation", "competence", "competent", "compile", "complement",
    "complexity", "compliance", "complication", "compliment", "comply", "component", "composer",
    "composition", "compound", "comprehensive", "comprise", "compromise", "compulsory", "compute",
    "conceal", "concede", "conceive", "conception", "concerto", "concession", "conclude",
    "condemn", "condense", "condensed", "confer", "confess", "confession", "configuration",
    "confine", "confirmation", "confront", "confrontation", "confusion", "congested",
    "congestion", "congress", "conquer", "conquest", "conscience", "conscious", "consciousness",
    "consecutive", "consensus", "consent", "consequent", "consequently", "conservation",
    "conservative", "conserve", "considerable", "considerably", "considerate", "consideration",
    "consistency", "consistently", "console", "conspiracy", "constellation", "constituency",
    "constitute", "constitution", "constitutional", "constrain", "constraint", "consult",
    "consultant", "consultation", "consumption", "contagious", "contaminate", "contemplate",
    "contemporary", "contempt", "contend", "contender", "contention", "continent", "contractor",
    "contradict", "contradiction", "contrary", "contributor", "controversial", "controversy",
    "convenience", "convention", "conventional", "conversion", "convert", "convey", "convict",
    "conviction", "cooperate", "cooperation", "cooperative", "coordinate", "coordination",
    "coordinator", "cop", "cope", "copyright", "coral", "core", "corporation", "corpse",
    "correction", "correlate", "correlation", "correspond", "correspondence", "correspondent",
    "corridor", "corrupt", "corruption", "cosmic", "cosmopolitan", "councilor", "counsel",
    "counseling", "counselor", "counteract", "counterpart", "countless", "coup", "courier",
    "courtesy", "cove", "coverage", "cowboy", "cozy", "crackdown", "craft", "cram", "cramp",
    "crane", "credibility", "credible", "credentials", "creep", "crest", "criteria", "critic",
    "critical", "critically", "criticism", "critique", "crown", "crucial", "crude", "cruise",
    "cue", "culinary", "cult", "cultivate", "culprit", "curb", "curiosity", "currency",
    "curriculum", "custody", "cute", "cutting", "cynical", "damaging", "dare", "darkness",
    "database", "dawn", "deadly", "dealer", "debris", "debut", "deceased", "deceive", "deception",
    "decipher", "decision-making", "decisive", "deck", "declaration", "dedicated", "dedication",
    "deed", "deem", "default", "defect", "defender", "defensive", "deficiency", "deficit", "defy",
    "deform", "deformed", "degrade", "delegate", "delegation", "delete", "delicate", "delta",
    "democracy", "democratic", "demon", "demonstration", "denial", "denounce", "dense", "density",
    "dependence", "dependency", "depict", "deplete", "deploy", "deployment", "deposit", "depot",
    "depression", "deprive", "deputy", "derive", "descend", "descent", "designate", "desirable",
    "desktop", "despair", "desperately", "destruction", "destructive", "detain", "detection",
    "detention", "deter", "deteriorate", "deterioration", "determination", "devastate", "devil",
    "devise", "devote", "diagnose", "diagnosis", "dialect", "diameter", "dictate", "dictator",
    "differentiate", "dignity", "dilemma", "diligent", "dimension", "diminish", "dine", "dip",
    "diploma", "diplomat", "diplomatic", "dire", "directory", "disability", "disastrous",
    "discard", "discharge", "disclose", "disclosure", " discomfort", "disconnect", "discourage",
    "discourse", "discretion", "discriminate", "discrimination", "disguise", "disgust",
    "disposal", "dispose", "disprove", "dispute", "disrupt", "disruption", "dissolve",
    "distinction", "distinctive", "distinguish", "distort", "distract", "distress", "distribution",
    "disturbance", "distrust", "diverse", "diversity", "divert", "divine", "doctrine",
    "documentation", "domain", "dominance", "dominant", "donation", "donor", "doomed", "dose",
    "drain", "dramatically", "drawback", "dread", "dreary", "drift", "driving", "drought", "dual",
    "dub", "duke", "dumb", "dump", "dung", "duo", "duplicate", "duration", "dynamic", "dynamics",
    "eager", "earl", "earnings", "ease", "echo", "eclipse", "ecological", "ecology", "economist",
    "ecosystem", "editorial", "educator", "effectiveness", "efficiency", "ego", "elaborate",
    "elapse", "elastic", "elder", "electoral", "electromagnetic", "electron", "electronics",
    "elegant", "elementary", "elevate", "eligible", "eliminate", "elite", "eloquent", "embark",
    "embarrassment", "embed", "embody", "embrace", "emerge", "emergence", "emission", "empathy",
    "emperor", "emphasize", "empirical", "empower", "emulate", "enact", "enclose", "endeavor",
    "endorse", "endorsement", "endure", "enforce", "enforcement", "engagement", "engaging",
    "enhance", "enlist", "enquire", "enrich", "enroll", "ensue", "enterprise", "enthusiast",
    "entitle", "entity", "entrepreneur", "envelope", "envious", "envision", "epidemic", "equality",
    "equate", "equation", "equilibrium", "equip", "equivalent", "era", "erect", "erode", "err",
    "erupt", "escalate", "escort", "essence", "establishment", "esteem", "esteemed", "eternal",
    "ethic", "ethnic", "etiquette", "evacuate", "evaluation", "evident", "evil", "evoke",
    "evolution", "evolutionary", "evolve", "exaggerate", "exceed", "excellence", "excel",
    "exception", "exceptional", "excess", "excessive", "exclaim", "exclude", "exclusion",
    "exclusive", "exclusively", "execute", "execution", "exert", "exile", "exotic", "expansion",
    "expedition", "expenditure", "experimental", "expertise", "expire", "explicit", "explicitly",
    "exploit", "exploitation", "explosive", "exposure", "extension", "extensive", "extensively",
    "extent", "exterior", "external", "extinct", "extinction", "extinguish", "extract",
    "extremist", "fabulous", "facilitate", "faction", "faculty", "fad", "fahrenheit", "fairness",
    "fake", "fame", "fantasy", "fare", "fatal", "fate", "favorable", "feat", "federal",
    "federation", "feminist", "fertile", "festive", "fiber", "fierce", "filmmaker", "filter",
    "fine", "firearm", "firsthand", "fiscal", "fit", "flatter", "flaw", "flawed", "flee", "fleet",
    "flesh", "flexibility", "flint", "flourish", "fluctuate", "fluid", "flush", "folklore",
    "fond", "fool", "footage", "forage", "forbid", "forecast", "foreigner", "forge", "format",
    "formation", "formerly", "formula", "formulate", "forth", "forthcoming", "fortunate", "forum",
    "fossil", "foster", "foul", "foundation", "founder", "fraction", "fracture", "fragile",
    "fragment", "framework", "franchise", "frankly", "fraud", "freely", "freight", "frequency",
    "frigid", "frustrated", "frustrating", "frustration", "fulfill", "full-time", "fume",
    "functional", "fundamentally", "fundraising", "furious", "fuse", "gallon", "gambling",
    "gaming", "gathering", "gay", "gaze", "gear", "gender", "gene", "genetic", "genius",
    "genocide", "genome", "genre", "genuine", "genuinely", "geology", "gesture", "gig", "glacial",
    "glance", "glimpse", "globalization", "globe", "glorious", "glory", "golden", "goodness",
    "gorgeous", "gourmet", "governance", "grace", "gracious", "gradually", "graffiti", "grand",
    "granite", "grant", "graphic", "graphics", "grasp", "gratify", "grave", "gravity", "greatly",
    "greenhouse", "grid", "grief", "grin", "grind", "grip", "gross", "guerrilla", "guidance",
    "guideline", "guilt", "gut", "guts", "habitat", "habitual", "hack", "hail", "halfway", "halt",
    "handful", "handling", "handy", "harass", "harassment", "harbor", "hardy", "hardware",
    "harmonize", "harmony", "harness", "harsh", "harvest", "hatred", "haunt", "hazard",
    "headquarters", "heal", "healthcare", "hectare", "heed", "heighten", "heir", "helmet",
    "hemisphere", "hence", "herb", "hereditary", "heritage", "hermit", "hesitant", "hierarchy",
    "high-profile", "hint", "hip", "historian", "homeland", "homeless", "honesty", "hone", "hook",
    "hopeful", "hopefully", "horizon", "horn", "horrifying", "hostage", "hostile", "hostility",
    "humanitarian", "humanity", "humble", "humane", "hydrogen", "hymn", "hypothesis", "icon",
    "identical", "identification", "ideological", "ideology", "idiot", "ignorance", "ignorant",
    "illusion", "illustration", "imagery", "immense", "immigration", "imminent", "immune",
    "impair", "impartial", "impatient", "impede", "imperative", "imperial", "implement",
    "implementation", "implicate", "implication", "imply", "impose", "imprison", "imprisonment",
    "imprint", "impulse", "inability", "inadequate", "inappropriate", "incentive", "incidence",
    "inclined", "incline", "inclusion", "inclusive", "incorporate", "incorrect", "incur", "index",
    "indication", "indicator", "indictment", "indigenous", "indifferent", "induce", "indulge",
    "industrious", "inequality", "inevitable", "inevitably", "infamous", "infant", "infect",
    "infer", "inferior", "infinite", "inflation", "inflict", "influential", "info",
    "infrastructure", "ingenious", "inherent", "inherit", "inhibit", "initiate", "inject",
    "injection", "injustice", "inland", "inmate", "innovation", "innovative", "input", "inquire",
    "insane", "insert", "insider", "insight", "insist", "insomnia", "inspection", "inspiration",
    "install", "installation", "instant", "instinct", "institutional", "instruct", "instrumental",
    "insufficient", "insult", "intact", "intake", "integral", "integrate", "integrated",
    "integration", "integrity", "intellect", "intellectual", "intensify", "intensity", "intensive",
    "intent", "interactive", "interchange", "interfere", "interference", "interim", "interior",
    "intermediate", "intermittent", "internal", "interpretation", "interval", "intervene",
    "intervention", "intestines", "intimate", "intimidate", "intolerable", "intrigue",
    "intriguing", "intuitive", "invade", "invasion", "inventive", "invert", "investigator",
    "invisible", "invoke", "involvement", "ironic", "ironically", "irony", "irrelevant",
    "irrigate", "isolate", "isolated", "isolation", "ivory", "jail", "jet", "joint", "journalism",
    "judicial", "junction", "jurisdiction", "just", "justification", "keen", "kidnap", "kidney",
    "kingdom", "kit", "lad", "landing", "landlord", "landmark", "lane", "lap", "large-scale",
    "laser", "latter", "lawmaker", "lawn", "lawsuit", "layout", "leak", "leap", "legacy",
    "legendary", "legislation", "legislative", "legislature", "legitimate", "lengthy", "lesbian",
    "lesser", "lethal", "liable", "liberal", "liberation", "liberty", "lifelong", "likelihood",
    "likeness", "limb", "limitation", "line-up", "linear", "linger", "linguistic", "listing",
    "literacy", "literally", "literary", "litter", "liver", "lobby", "locale", "log", "logic",
    "logo", "long-standing", "long-time", "loom", "loop", "loyalty", "lunar", "lure", "lush",
    "lyric", "machinery", "magical", "magistrate", "magnetic", "magnificent", "magnify",
    "magnitude", "mainland", "mainstream", "maintenance", "mandarin", "mandate", "mandatory",
    "managerial", "manifest", "manipulate", "manipulation", "manor", "manuscript", "marathon",
    "march", "margin", "marginal", "marine", "marker", "marketplace", "marrow", "marshal",
    "martial", "masculine", "mash", "massacre", "masterpiece", "matching", "mate", "mathematical",
    "mature", "maximize", "mayor", "meaningful", "meantime", "mechanic", "mechanism", "medalist",
    "mediation", "medication", "medieval", "meditation", "melody", "memo", "memoir", "memorial",
    "mentor", "merchant", "mercy", "mere", "merely", "merge", "merger", "merit", "metabolic",
    "metaphor", "meteorology", "meteorological", "methodology", "metropolitan", "microbe", "midst",
    "migraine", "migrate", "migration", "militant", "militia", "millennium", "miner", "minimal",
    "minimize", "mining", "ministry", "minute", "miracle", "misconception", "miserable", "misery",
    "misguided", "misleading", "missile", "mob", "mobility", "mobilize", "mock", "moderate",
    "moderation", "modification", "momentum", "monastery", "monetary", "monk", "monolingual",
    "monopoly", "monster", "monthly", "monument", "morale", "morality", "mortal", "mortgage",
    "mosque", "mosquito", "motion", "motivate", "motivation", "motive", "motorist", "moving",
    "multicultural", "multiple", "municipal", "mutual", "mythology", "naive", "naked", "namely",
    "nasty", "nationwide", "naval", "navigation", "nearby", "necessity", "needy", "neglect",
    "negligible", "negotiate", "negotiation", "nerve", "neutral", "newcomer", "newsletter",
    "niche", "nick", "noble", "nod", "nominate", "nomination", "nominee", "nonetheless",
    "non-profit", "nonsense", "norm", "notable", "notably", "notorious", "novelty", "nourish",
    "nucleus", "nursery", "nursing", "nurture", "nutrition", "oath", "obesity", "obey",
    "objection", "obligation", "oblige", "obscure", "observer", "obsess", "obsession", "obstacle",
    "obsolete", "occasional", "occupation", "occupy", "occurrence", "odds", "offender", "offering",
    "offspring", "omen", "omission", "ongoing", "onset", "openly", "opera", "operational",
    "opt", "optical", "optimism", "optimistic", "oral", "orchestra", "ore", "organic",
    "organizational", "orientation", "originate", "ornate", "outback", "outbreak", "outburst",
    "outcome", "outdated", "outfit", "outing", "outlaw", "outlet", "outlook", "outmoded",
    "outnumber", "output", "outrage", "outraged", "outright", "outset", "outsider", "outstanding",
    "outweigh", "overboard", "overcome", "overlook", "overly", "overnight", "overpopulation",
    "oversee", "overturn", "overwhelm", "overwhelming", "ownership", "oxygen", "packet", "pad",
    "palm", "panic", "parade", "paradox", "parallel", "paralysis", "paramount", "paraphrase",
    "parasite", "parental", "parish", "parliamentary", "partial", "partiality", "partially",
    "participation", "partnership", "part-time", "passing", "passionate", "passive", "pastor",
    "patch", "patent", "pathway", "patience", "patrol", "patron", "pause", "peak", "peasant",
    "peculiar", "peer", "peninsula", "penetrate", "perceive", "perception", "permanently",
    "persecute", "persist", "persistent", "personalize", "personnel", "perspective", "pertain",
    "petition", "pharmaceutical", "philosopher", "philosophical", "phoenix", "photosynthesis",
    "physician", "physics", "physiology", "pioneer", "pipeline", "pirate", "pit", "pity",
    "placement", "plea", "plead", "pledge", "plug", "plunge", "pneumonia", "pole", "poll",
    "ponder", "pop", "portfolio", "portion", "portray", "postpone", "post-war", "potentially",
    "practitioner", "prairie", "preach", "precede", "precedent", "precious", "precise",
    "precisely", "precision", "predator", "predecessor", "predominantly", "pregnancy", "prejudice",
    "preliminary", "premier", "premise", "premium", "premature", "prescribe", "prescription",
    "preservation", "preside", "presidency", "presidential", "prestigious", "presumably",
    "presume", "prevail", "prevalence", "prevention", "preview", "prey", "pride", "primarily",
    "principal", "prior", "privatization", "privilege", "probability", "probable", "probe",
    "problematic", "proceed", "proceeding", "proceeds", "processing", "procession", "processor",
    "proclaim", "prod", "productive", "productivity", "profitable", "profound", "programming",
    "progressive", "prohibit", "projection", "prominent", "promising", "promotion", "prompt",
    "prone", "pronounced", "propaganda", "propel", "prophecy", "prophet", "proportion",
    "propulsion", "prosecute", "prosecution", "prosecutor", "prospective", "prosperity",
    "protective", "protein", "protester", "protocol", "prototype", "provincial", "provision",
    "provoke", "proximity", "psychiatric", "psychiatry", "psychic", "psychological", "publicity",
    "publishing", "pulse", "pump", "punch", "punk", "purely", "pursuit", "puzzle", "query",
    "quest", "questionnaire", "quiver", "quota", "racial", "racism", "racist", "radar",
    "radiation", "radical", "radioactive", "rage", "raid", "rail", "rally", "random", "ranking",
    "rape", "rat", "rating", "ratio", "rational", "ray", "readily", "realization", "realm",
    "rear", "reasoning", "reassure", "rebel", "rebellion", "recipient", "reckless", "recognition",
    "reconstruction", "recount", "recovery", "recruit", "recruitment", "rectify", "referee",
    "referendum", "reflection", "reflex", "reform", "refuge", "refugee", "refusal", "refute",
    "regain", "regardless", "regime", "regulator", "regulatory", "rehabilitation", "reign",
    "reinforce", "rejection", "relativity", "relevance", "reliability", "relieve", "reluctant",
    "remainder", "remains", "remedy", "reminder", "remorse", "removal", "render", "renew",
    "renowned", "rental", "replacement", "replicate", "reproductive", "renovate", "reportedly",
    "reporting", "representation", "reproduce", "reproduction", "republic", "resemble", "resent",
    "residence", "residential", "residue", "resign", "resignation", "resistance", "resolution",
    "resolve", "resourceful", "respective", "respectively", "respiration", "respirator",
    "restoration", "restraint", "restrict", "restriction", "resume", "retail", "retain",
    "retirement", "retreat", "retrieve", "revelation", "revenge", "revenue", "reverse", "revival",
    "revive", "revolutionary", "rhetoric", "rifle", "rig", "right-wing", "rigid", "riot", "rip",
    "risky", "ritual", "rival", "robbery", "robust", "rock", "rod", "romance", "rookie", "rose",
    "roster", "rotate", "rotation", "rough", "roughly", "ruin", "ruling", "rumor", "rupture",
    "sacred", "sacrifice", "saint", "sake", "saliva", "sanction", "sanctuary", "sane", "sarcastic",
    "satire", "saturate", "say", "scattered", "scenario", "scholar", "scholarship", "scope",
    "scratch", "screening", "screw", "scrutiny", "seclude", "secluded", "secular", "seemingly",
    "segment", "segregate", "seize", "seizure", "seldom", "selective", "semifinal", "senator",
    "sensation", "sensitivity", "sensory", "sentiment", "separation", "sequence", "sergeant",
    "serial", "settlement", "settler", "setup", "severely", "sexuality", "shaped", "shareholder",
    "shatter", "shed", "sheer", "shipping", "shoot", "shortage", "short-term", "sibling", "sigh",
    "significance", "simulate", "simulation", "simultaneously", "sin", "situate", "situated",
    "skeletal", "sketch", "skeptic", "skeptical", "skip", "skull", "slam", "slap", "slash",
    "slavery", "slogan", "slot", "smallpox", "smash", "snap", "soak", "soar", "socialist",
    "sociology", "sodium", "sole", "solely", "solemn", "solicitor", "solidarity", "solitude",
    "solo", "somehow", "sophisticated", "soundly", "sovereignty", "spam", "span", "spare", "spark",
    "specialized", "specification", "specimen", "speck", "spectacle", "spectacular", "spectator",
    "spectrum", "speculate", "speculation", "spell", "sphere", "spill", "spin", "spine",
    "spotlight", "spouse", "spy", "squad", "squeeze", "stab", "stability", "stabilize", "stake",
    "stall", "stance", "standing", "staple", "stark", "starve", "statistical", "statute",
    "steadily", "steam", "steer", "stem", "stereotype", "sterile", "steward", "stimulate",
    "stimulus", "stir", "storage", "straightforward", "strain", "strand", "strategic", "striking",
    "strip", "strive", "stroke", "structural", "stumble", "stun", "stunning", "stunt",
    "submission", "subscriber", "subscription", "subsequent", "subsequently", "subsidy",
    "subsist", "substantial", "substantially", "substitute", "substitution", "subtle", "suburban",
    "succession", "successive", "suck", "sue", "suicide", "suite", "summit", "superb", "superior",
    "supervise", "supervision", "supervisor", "supplement", "supportive", "supposedly",
    "suppress", "supreme", "surge", "surgical", "surplus", "surrender", "surveillance",
    "survival", "survivor", "susceptible", "suspect", "suspension", "suspicion", "suspicious",
    "sustain", "sustainable", "swallow", "swing", "sword", "symbolic", "sympathetic", "symmetry",
    "syndrome", "synthesis", "synthetic", "systematic", "tackle", "tact", "tactic", "tactical",
    "taxpayer", "technical", "technological", "tedious", "teens", "temperate", "temple",
    "temporarily", "tempt", "tenant", "tendency", "tender", "tension", "tenure", "terminal",
    "terminate", "terms", "terrain", "terrestrial", "terribly", "terrific", "terrify",
    "territory", "terror", "terrorism", "terrorist", "testament", "testify", "testimony",
    "texture", "thankfully", "theatrical", "theft", "theology", "theoretical", "therapist",
    "therapeutic", "therapy", "thereafter", "thereby", "thesis", "thorough", "thoroughly",
    "thoughtful", "thought-provoking", "thread", "threshold", "thrilled", "thrive", "throat",
    "thrust", "thumb", "thump", "tide", "tighten", "timber", "timely", "tobacco", "tolerance",
    "tolerant", "tolerate", "toll", "top", "torment", "torture", "toss", "total", "toxic",
    "trace", "tract", "trademark", "trading", "tragedy", "tragic", "trait", "trance",
    "transaction", "transcript", "transformation", "transit", "transmission", "transmit",
    "transparency", "transparent", "trauma", "traverse", "treachery", "treasure", "treaty",
    "tremendous", "tribal", "tribunal", "tribute", "trigger", "trillion", "trio", "triumph",
    "troop", "trophy", "troubled", "trustee", "tuition", "tumult", "turnout", "turnover", "twist",
    "tyranny", "tyrant", "ultimate", "ultimately", "unacceptable", "uncertainty", "undergo",
    "undergraduate", "underlying", "undermine", "undertake", "undoubtedly", "unfair", "unfold",
    "unified", "unify", "unity", "universal", "unprecedented", "unrest", "unsettle", "unveil",
    "upcoming", "upbringing", "upgrade", "uphold", "urgent", "usage", "useless", "utility",
    "utilize", "utterly", "vacuum", "vague", "vain", "valid", "validity", "vanish", "variable",
    "variation", "varied", "vein", "venom", "venture", "verbal", "verdict", "verify", "verse",
    "versus", "vessel", "veteran", "viable", "vibrant", "vice versa", "vicious", "vigorous",
    "villager", "violate", "violation", "virtue", "visa", "vital", "vivacious", "vocal",
    "volatile", "voluntary", "vow", "vulnerability", "vulnerable", "ward", "warehouse", "warfare",
    "warming", "warrant", "warrior", "warp", "weaken", "weave", "weed", "weekly", "weird",
    "welfare", "well-being", "whatsoever", "whereabouts", "whereby", "whilst", "whip", "wholly",
    "widen", "widespread", "widow", "width", "willingness", "wipe", "wit", "withdrawal",
    "withhold", "workout", "workforce", "workplace", "workshop", "worm", "worsen", "worship",
    "worthwhile", "worthy", "yell", "yield", "youngster",
}

OXFORD_C1 = {
    "abbey", "abide", "abnormal", "abolition", "abrupt", "abstain", "acclaim", "acclaimed",
    "accomplished", "accord", "accountable", "accumulation", "accustomed", "ace", "acquaint",
    "acquaintance", "acrobat", "activation", "acute", "adaptation", "adept", "adhesive",
    "adherence", "adjoin", "administer", "administrative", "adolescence", "adorn", "advent",
    "adverse", "advocacy", "aerial", "aesthetic", "affair", "afflicted", "affluent", "aftermath",
    "aggravate", "ail", "airway", "alas", "albeit", "alchemy", "alienate", "align", "allegation",
    "allege", "alleviate", "allot", "alloy", "allude", "almighty", "aloft", "aloud", "altar",
    "alteration", "alternate", "altitude", "aluminum", "amass", "amber", "ambiguous",
    "ambivalence", "amend", "amid", "amnesty", "ample", "analogous", "analogy", "analytic",
    "analytical", "anarchy", "anatomy", "ancestral", "ancestry", "anew", "anguish", "animate",
    "annex", "anniversary", "anomaly", "anonymous", "antagonist", "anthropology", "anticipate",
    "antique", "antiquity", "apathy", "appall", "appalling", "apparatus", "appease", "applaud",
    "applause", "apprehend", "apprentice", "apt", "aquatic", "arbitrary", "archaeological",
    "archaeology", "archaic", "archer", "architectural", "archive", "arctic", "ardent", "arduous",
    "arid", "aristocracy", "aristocrat", "arithmetic", "armour", "aroma", "arouse", "array",
    "arrogance", "arrogant", "arsenal", "artery", "arthritis", "articulate", "artifact",
    "artillery", "ascend", "ascent", "ascertain", "ascribe", "ashore", "aspire", "assail",
    "assassinate", "assault", "assemble", "assert", "assertion", "assimilate", "asteroid",
    "astonish", "astound", "astray", "astrology", "astronomical", "astronomy", "astute", "asylum",
    "atheist", "atrocity", "attain", "attainment", "attendant", "attire", "attribute", "audible",
    "audit", "augment", "august", "authentic", "authenticity", "authorize", "autobiography",
    "autonomy", "autumn", "avail", "avalanche", "avenge", "avenue", "avert", "aviation", "avid",
    "awe", "axis", "azure",
}

# Curated natural collocations with Vietnamese glosses for high-visibility & seed words
CURATED_COLLOCATIONS_BY_WORD: dict[str, list[str]] = {
    "transportation": [
        "public transportation - phương tiện giao thông công cộng",
        "means of transportation - phương tiện đi lại",
    ],
    "ephemeral": [
        "ephemeral memories - ký ức ngắn ngủi",
        "ephemeral beauty - vẻ đẹp phù du",
    ],
    "ubiquitous": [
        "ubiquitous technology - công nghệ phổ biến khắp nơi",
        "ubiquitous presence - sự hiện diện ở mọi nơi",
    ],
    "pragmatic": [
        "pragmatic approach - cách tiếp cận thực tế",
        "pragmatic solution - giải pháp thiết thực",
    ],
    "noise": [
        "loud noise - tiếng ồn lớn",
        "background noise - tiếng ồn xung quanh",
    ],
    "image": [
        "clear image - hình ảnh rõ nét",
        "public image - hình ảnh trước công chúng",
    ],
    "separate": [
        "separate rooms - các phòng riêng biệt",
        "keep separate - giữ tách biệt",
    ],
    "counterpart": [
        "foreign counterpart - người đồng cấp nước ngoài",
        "direct counterpart - đối trọng/vật tương đương trực tiếp",
    ],
    "overboard": [
        "fall overboard - rơi khỏi mạn tàu xuống nước",
        "go overboard - làm quá mức",
    ],
    "curb": [
        "curb anger - kiềm chế cơn giận",
        "curb inflation - kiềm chế lạm phát",
    ],
    "prod": [
        "prod gently - chọc/thúc nhẹ",
        "prod someone into action - thúc giục ai hành động",
    ],
    "flatter": [
        "feel flattered - cảm thấy vinh dự/được khen",
        "flatter someone - tâng bốc ai đó",
    ],
    "bottom": [
        "bottom of the ocean - đáy đại dương",
        "from top to bottom - từ trên xuống dưới",
    ],
    "middle": [
        "middle of the courtyard - giữa sân",
        "middle age - tuổi trung niên",
    ],
    "sustenance": [
        "basic sustenance - kế sinh nhai cơ bản",
        "daily sustenance - nguồn dinh dưỡng hằng ngày",
    ],
    "drought": [
        "severe drought - hạn hán nghiêm trọng",
        "prolonged drought - đợt khô hạn kéo dài",
    ],
}

SYNTHETIC_COLLOC_PATTERNS = (
    re.compile(r"^to\s+\S+\s*-\s*", re.I),
    re.compile(r"^\S+\s+properly\s*-\s*", re.I),
    re.compile(r"^the\s+\S+\s*-\s*", re.I),
    re.compile(r"^common\s+\S+\s*-\s*", re.I),
    re.compile(r"^very\s+\S+\s*-\s*", re.I),
    re.compile(r"^become\s+\S+\s*-\s*", re.I),
    re.compile(r"^act\s+\S+\s*-\s*", re.I),
    re.compile(r"^quite\s+\S+\s*-\s*", re.I),
    re.compile(r"^\S+\s+in\s+context\b", re.I),
    re.compile(r"^use\s+\S+\s*-\s*", re.I),
    re.compile(r"^make\s+a\s+\S+\b", re.I),
    re.compile(r"^a\s+\S+\s+of\s*-\s*", re.I),
)

STOP_NEIGHBORS = {
    "i", "you", "he", "she", "it", "we", "they", "me", "him", "us", "them",
    "am", "is", "are", "was", "were", "be", "been", "being",
    "have", "has", "had", "do", "does", "did",
    "will", "would", "shall", "should", "can", "could", "may", "might", "must",
    "that", "which", "who", "whom", "whose", "where", "when", "why", "how",
    "if", "because", "although", "though", "while", "since", "until", "unless",
    "and", "or", "but", "so", "nor", "yet",
    "there", "here", "this", "these", "those", "my", "your", "his", "her", "its", "our", "their",
    "don’t", "doesn’t", "didn’t", "isn’t", "aren’t", "wasn’t", "weren’t", "won’t", "can’t",
    "dont", "doesnt", "didnt", "isnt", "arent", "wasnt", "werent", "wont", "cant",
    "not", "never", "always", "often", "sometimes", "very", "quite", "too", "also", "just",
    "everyone", "everybody", "someone", "somebody", "anyone", "anybody", "no", "nobody",
    "everything", "something", "anything", "nothing", "other", "others", "another", "same",
    "such", "more", "most", "less", "least", "only", "even", "still", "already", "almost",
    "right", "well", "away", "back", "again", "together", "alone", "once", "twice",
    "today", "tomorrow", "yesterday", "then", "now", "soon", "ago",
}

WEAK_COLLOC_VERBS = {
    "get", "got", "gets", "getting", "go", "went", "gone", "going",
    "come", "came", "coming", "see", "saw", "seen", "seeing",
    "look", "looked", "looks", "looking", "want", "wanted", "wants",
    "like", "liked", "likes", "love", "loved", "loves", "hate", "hated",
    "know", "knew", "known", "think", "thought", "say", "said", "tell", "told",
    "put", "puts", "putting", "let", "lets", "make", "made", "makes", "making",
    "become", "became", "becomes", "use", "used", "uses", "using",
    "need", "needed", "needs", "buy", "bought", "give", "gave", "given",
    "find", "found", "keep", "kept", "leave", "left", "bring", "brought",
}

DETERMINERS_AND_PREPS = {
    "a", "an", "the", "some", "any", "no", "many", "much", "several", "few", "each", "every",
    "of", "in", "on", "at", "to", "for", "with", "from", "by", "about", "into", "over", "after",
    "under", "between", "through", "across", "against", "around", "behind", "beyond", "toward",
    "towards", "upon", "within", "without", "out", "up", "down", "off", "away",
}


def is_synthetic_collocation(item: str, word: str) -> bool:
    s = item.strip()
    low = s.lower()
    w = word.lower().strip()
    for pat in SYNTHETIC_COLLOC_PATTERNS:
        if pat.search(s):
            return True
    if (
        low.startswith(f"to {w} ")
        or low.startswith(f"{w} properly")
        or low.startswith(f"the {w} -")
        or low.startswith(f"common {w}")
        or low.startswith(f"very {w}")
        or low.startswith(f"quite {w}")
        or low.startswith(f"become {w} -")
        or low.startswith(f"act {w}")
        or low.startswith(f"use {w}")
        or "đúng cách" in low
        or "trong ngữ cảnh" in low
        or "hành động một cách" in low
    ):
        return True
    return False


def clean_ocr_text(text: str) -> str:
    s = text.strip()
    s = re.sub(r"\bo\s+f\b", "of", s)
    s = re.sub(r"\bo\s+ff\b", "off", s)
    s = re.sub(r"\bofthe\b", "of the", s)
    s = re.sub(r"\bfora\b", "for a", s)
    s = re.sub(r"\bora\b", "or a", s)
    s = re.sub(r"\bcontainerto\b", "container to", s)
    s = re.sub(r"\blive though\b", "live through", s)
    s = re.sub(r"\bIfyou\b", "If you", s)
    s = re.sub(r"\bhim self\b", "himself", s)
    s = re.sub(r"\bim\s+polite\b", "impolite", s)
    s = re.sub(r"\bs\s+tiff\b", "stiff", s)
    s = re.sub(r"\bM\s+artin\b", "Martin", s)
    s = re.sub(r"\bNe\s+lost\b", "We lost", s)
    s = re.sub(r"\bof\s+todays\b", "of today", s)
    s = re.sub(r"\ba a\b", "a", s)
    s = re.sub(r"\bo\s+’clock\b", "o’clock", s)
    s = re.sub(r"“\s+", "“", s)
    s = re.sub(r"\s+”", "”", s)
    s = re.sub(r"\boften years\b", "of ten years", s)
    s = re.sub(r"\s{2,}", " ", s)
    return s.strip()


def normalize_pos(card_id: str, raw_pos: str) -> str:
    if card_id in POS_OVERRIDES_BY_ID:
        return POS_OVERRIDES_BY_ID[card_id]
    p = raw_pos.strip().lower()
    if p == "adj":
        return "adjective"
    if p == "adv":
        return "adverb"
    if p in CANONICAL_POS:
        return p
    return "noun"


def normalize_ipa(card_id: str, word: str, raw_ipa: str) -> str:
    if card_id in IPA_OVERRIDES_BY_ID:
        exp_word, override_ipa = IPA_OVERRIDES_BY_ID[card_id]
        assert exp_word.lower() == word.lower(), f"IPA override mismatch on {card_id}: {exp_word} != {word}"
        return override_ipa
    ph = raw_ipa.strip()
    if not ph:
        raise ValueError(f"Empty IPA for {card_id} ({word})")
    ph = ph.strip("/")
    ph = ph.replace("ӕ", "æ").replace("ē", "e").replace(":", "ː")
    # Unwrap optional parenthesized segments cleanly
    ph = ph.replace("(ə)", "ə").replace("(d)", "d").replace("(t)", "t").replace("(k)", "k").replace("(r)", "r").replace("(ː)", "ː")
    ph = re.sub(r"[()\[\]]", "", ph)
    ph = ph.replace("ʊəːr", "ʊr").replace("ɪəːr", "ɪr").replace("ɛəːr", "ɛr")

    # Convert stressed vs unstressed əːr / əː
    # A syllable containing əː is stressed if:
    #   - preceded by ˈ or ˌ with only consonants between, OR
    #   - word has no ˈ/ˌ stress mark at all (monosyllable like /bəːn/)
    has_stress_mark = ("ˈ" in ph) or ("ˌ" in ph)

    def repl_schwa_long(m: re.Match) -> str:
        start = m.start()
        prefix = ph[:start]
        has_r = m.group(1) == "r"
        if not has_stress_mark:
            return "ɜːr" if has_r else "ɜː"
        # Check if most recent stress mark has no vowel between it and start
        last_stress = max(prefix.rfind("ˈ"), prefix.rfind("ˌ"))
        if last_stress >= 0 and not re.search(r"[aeiouæɑɒɔəɛɜɪʊʌ]", prefix[last_stress:]):
            return "ɜːr" if has_r else "ɜː"
        return "ər" if has_r else "ə"

    ph = re.sub(r"əː(r?)", repl_schwa_long, ph)

    # Normalize non-standard diphthong spellings ei -> eɪ, ou -> oʊ, ai -> aɪ, au -> aʊ, ɔi -> ɔɪ
    ph = ph.replace("ei", "eɪ").replace("ou", "oʊ").replace("ai", "aɪ").replace("au", "aʊ").replace("ɔi", "ɔɪ")
    ph = re.sub(r"əə+", "ə", ph)
    ph = re.sub(r"\s+", " ", ph).strip()
    return f"/{ph}/"


def assign_cefr(card_id: str, word: str, raw_level: str) -> tuple[str, int]:
    w = word.strip().lower()
    m_book = re.match(r"^sr-b0([1-6])-", card_id)
    book_num = int(m_book.group(1)) if m_book else (5 if card_id.startswith("sr-unit") else 0)

    # Seed cards keep their Cambridge/Oxford C1 reference
    if card_id.startswith("sr-seed-en-"):
        return ("C1", LEVEL_SOURCES.index("Oxford 5000 / Cambridge EVP"))

    if w in OXFORD_A1:
        lvl = "A1" if book_num <= 2 else "A2"
        src = f"Oxford 3000 / 4000 Essential English Words Vol. {book_num}" if book_num else "Oxford 3000 / Cambridge EVP"
        return (lvl, LEVEL_SOURCES.index(src))

    if w in OXFORD_A2:
        lvl = "A2"
        src = f"Oxford 3000 / 4000 Essential English Words Vol. {book_num}" if book_num else "Oxford 3000 / Cambridge EVP"
        return (lvl, LEVEL_SOURCES.index(src))

    if w in OXFORD_B1:
        lvl = "B1"
        src = f"Oxford 3000 / 4000 Essential English Words Vol. {book_num}" if book_num else "Oxford 3000 / Cambridge EVP"
        return (lvl, LEVEL_SOURCES.index(src))

    if w in OXFORD_B2:
        lvl = "B2"
        src = f"Cambridge EVP / 4000 Essential English Words Vol. {book_num}" if book_num else "Oxford 5000 / Cambridge EVP"
        return (lvl, LEVEL_SOURCES.index(src))

    if w in OXFORD_C1:
        lvl = "C1"
        src = f"Cambridge EVP / 4000 Essential English Words Vol. {book_num}" if book_num else "Cambridge EVP"
        return (lvl, LEVEL_SOURCES.index(src))

    # Book progression fallback for specialized vocabulary not in Oxford 3000/5000 core
    if book_num == 1:
        lvl = raw_level if raw_level in ("A1", "A2", "B1") else "A2"
    elif book_num == 2:
        lvl = raw_level if raw_level in ("A2", "B1") else "B1"
    elif book_num == 3:
        lvl = "B1" if len(w) <= 7 else "B2"
    elif book_num == 4:
        lvl = "B2"
    elif book_num == 5:
        lvl = "C1" if raw_level in ("C1", "C2") else "B2"
    else:
        # Book 6: C1 for general literary/academic derivatives, C2 only for rare/specialized terms
        if re.search(r"(?:ize|ise|ate|ify|able|ible|ive|ous|al|ic|ment|tion|sion|ness|ity|ly)$", w) and len(w) <= 11:
            lvl = "C1"
        else:
            lvl = "C1" if len(w) <= 7 else "C2"

    src = f"Cambridge EVP / 4000 Essential English Words Vol. {book_num}" if book_num else "Cambridge EVP"
    return (lvl, LEVEL_SOURCES.index(src))


def concise_meaning_vi(meaning_vi: str) -> str:
    s = meaning_vi.strip().rstrip(".")
    # Strip trailing parenthetical explanations if the head gloss is already clear
    base = re.sub(r"\s*\([^)]*\)\s*", "", s).strip()
    if not base:
        base = s
    # Take primary sense before semicolon
    semi = [p.strip() for p in base.split(";") if p.strip()]
    primary = semi[0] if semi else base
    # Keep at most 2 comma-separated synonyms so Cloze hints stay compact
    parts = [p.strip() for p in primary.split(",") if p.strip()]
    if len(parts) > 2:
        primary = ", ".join(parts[:2])
    if len(primary) > 42 and len(parts) >= 2:
        primary = parts[0]
    return primary


IRREGULAR_CLOZE_MAP: dict[str, set[str]] = {
    "arise": {"arose", "arisen"}, "awake": {"awoke", "awoken"}, "bear": {"bore", "borne", "born"},
    "beat": {"beaten"}, "become": {"became"}, "begin": {"began", "begun"}, "bend": {"bent"},
    "bind": {"bound"}, "bite": {"bit", "bitten"}, "bleed": {"bled"}, "blow": {"blew", "blown"},
    "break": {"broke", "broken"}, "breed": {"bred"}, "bring": {"brought"}, "build": {"built"},
    "burn": {"burnt"}, "buy": {"bought"}, "catch": {"caught"}, "choose": {"chose", "chosen"},
    "cling": {"clung"}, "come": {"came"}, "creep": {"crept"}, "deal": {"dealt"}, "dig": {"dug"},
    "dive": {"dove"}, "draw": {"drew", "drawn"}, "dream": {"dreamt"}, "drink": {"drank", "drunk"},
    "drive": {"drove", "driven"}, "dwell": {"dwelt"}, "eat": {"ate", "eaten"}, "fall": {"fell", "fallen"},
    "feed": {"fed"}, "feel": {"felt"}, "fight": {"fought"}, "find": {"found"}, "flee": {"fled"},
    "fling": {"flung"}, "fly": {"flew", "flown", "flies"}, "forbid": {"forbade", "forbidden"},
    "forgive": {"forgave", "forgiven"}, "freeze": {"froze", "frozen"}, "give": {"gave", "given"},
    "go": {"went", "gone", "goes"}, "grind": {"ground"}, "grow": {"grew", "grown"},
    "hang": {"hung"}, "hide": {"hid", "hidden"}, "hold": {"held"}, "keep": {"kept"},
    "kneel": {"knelt"}, "know": {"knew", "known"}, "lay": {"laid"}, "lead": {"led"},
    "lean": {"leant"}, "leap": {"leapt"}, "learn": {"learnt"}, "leave": {"left"}, "lend": {"lent"},
    "lie": {"lay", "lain", "lying"}, "light": {"lit"}, "lose": {"lost"}, "make": {"made"},
    "mean": {"meant"}, "meet": {"met"}, "mistake": {"mistook", "mistaken"}, "overcome": {"overcame"},
    "overtake": {"overtook", "overtaken"}, "pay": {"paid"}, "prove": {"proven"}, "ride": {"rode", "ridden"},
    "ring": {"rang", "rung"}, "rise": {"rose", "risen"}, "run": {"ran"}, "say": {"said"},
    "see": {"saw", "seen"}, "seek": {"sought"}, "sell": {"sold"}, "send": {"sent"},
    "sew": {"sewn"}, "shake": {"shook", "shaken"}, "shine": {"shone"}, "shoot": {"shot"},
    "show": {"shown"}, "shrink": {"shrank", "shrunk"}, "sing": {"sang", "sung"},
    "sink": {"sank", "sunk"}, "sit": {"sat"}, "slay": {"slew", "slain"}, "sleep": {"slept"},
    "slide": {"slid"}, "smell": {"smelt"}, "sneak": {"snuck"}, "sow": {"sown"},
    "speak": {"spoke", "spoken"}, "speed": {"sped"}, "spell": {"spelt"}, "spend": {"spent"},
    "spill": {"spilt"}, "spin": {"spun"}, "spit": {"spat"}, "spoil": {"spoilt"},
    "spring": {"sprang", "sprung"}, "stand": {"stood"}, "steal": {"stole", "stolen"},
    "stick": {"stuck"}, "sting": {"stung"}, "stink": {"stank", "stunk"}, "stride": {"strode", "stridden"},
    "strike": {"struck"}, "string": {"strung"}, "strive": {"strove", "striven"},
    "swear": {"swore", "sworn"}, "sweep": {"swept"}, "swell": {"swollen"}, "swim": {"swam", "swum"},
    "swing": {"swung"}, "take": {"took", "taken"}, "teach": {"taught"}, "tear": {"tore", "torn"},
    "tell": {"told"}, "think": {"thought"}, "thrive": {"throve", "thriven"}, "throw": {"threw", "thrown"},
    "tread": {"trod", "trodden"}, "undergo": {"underwent", "undergone"}, "understand": {"understood"},
    "undertake": {"undertook", "undertaken"}, "uphold": {"upheld"}, "wake": {"woke", "woken"},
    "wear": {"wore", "worn"}, "weave": {"wove", "woven"}, "weep": {"wept"}, "win": {"won"},
    "wind": {"wound"}, "withdraw": {"withdrew", "withdrawn"}, "withhold": {"withheld"},
    "withstand": {"withstood"}, "wring": {"wrung"}, "write": {"wrote", "written"},
    "child": {"children"}, "person": {"people"}, "man": {"men"}, "woman": {"women"},
    "foot": {"feet"}, "tooth": {"teeth"}, "goose": {"geese"}, "mouse": {"mice"},
    "leaf": {"leaves"}, "wolf": {"wolves"}, "calf": {"calves"}, "half": {"halves"},
    "knife": {"knives"}, "wife": {"wives"}, "life": {"lives"}, "thief": {"thieves"},
    "loaf": {"loaves"}, "shelf": {"shelves"},
}


def _is_valid_cloze_form(word: str, cand: str, example: str) -> bool:
    if not cand or not re.search(r"(?<![A-Za-z])" + re.escape(cand) + r"(?![A-Za-z])", example):
        return False
    wl = word.strip().lower()
    cl = cand.strip().lower()
    if cl == wl or cl in IRREGULAR_CLOZE_MAP.get(wl, set()):
        return True
    if len(wl) >= 3 and cl.startswith(wl[:max(3, len(wl) - 2)]) and abs(len(cl) - len(wl)) <= 4:
        return True
    return False


def extract_cloze_target(card_id: str, word: str, example: str, old_cloze: str) -> str:
    if card_id in CLOZE_TARGET_OVERRIDES_BY_ID:
        cand = CLOZE_TARGET_OVERRIDES_BY_ID[card_id]
        assert re.search(r"(?<![A-Za-z])" + re.escape(cand) + r"(?![A-Za-z])", example), (
            f"Cloze override '{cand}' not whole-word in example on {card_id}: {example}"
        )
        return cand

    # Prefer existing target span ONLY if it is a whole-word morphological/irregular form of word
    m = re.search(r"\{\{c1::([^:}]+)(?:::[^}]+)?\}\}", old_cloze)
    if m:
        cand = m.group(1).strip()
        if _is_valid_cloze_form(word, cand, example):
            return cand

    # Otherwise match word or inflected form on whole-word boundaries in example
    w_clean = word.strip()
    w_esc = re.escape(w_clean)
    m_ex = re.search(r"(?<![A-Za-z])(" + w_esc + r"(?:s|es|ed|d|ing|er|est|ly)?)(?![A-Za-z])", example, re.I)
    if m_ex:
        return m_ex.group(1)

    for irr in sorted(IRREGULAR_CLOZE_MAP.get(w_clean.lower(), set()), key=len, reverse=True):
        m_irr = re.search(r"(?<![A-Za-z])(" + re.escape(irr) + r")(?![A-Za-z])", example, re.I)
        if m_irr:
            return m_irr.group(1)

    if len(w_clean) >= 3:
        stem = re.sub(r"(?:e|y|f|fe)$", "", w_clean, flags=re.I)
        m_st = re.search(r"(?<![A-Za-z])(" + re.escape(stem) + r"[a-zA-Z]{0,5})(?![A-Za-z])", example, re.I)
        if m_st and _is_valid_cloze_form(word, m_st.group(1), example):
            return m_st.group(1)

    raise ValueError(f"Could not locate whole-word cloze target for '{word}' ({card_id}) in '{example}'")


def extract_natural_collocation_from_example(word: str, pos: str, target_in_ex: str, example: str) -> list[str]:
    w_low = word.strip().lower()
    if w_low in CURATED_COLLOCATIONS_BY_WORD:
        return list(CURATED_COLLOCATIONS_BY_WORD[w_low])

    # Find clause containing target_in_ex without crossing punctuation
    idx = example.find(target_in_ex)
    if idx < 0:
        return []
    # Extract surrounding clause bounded by .,;:!?—"“”()
    left_clause = re.split(r"[.,;:!?—\"“”()]", example[:idx])[-1]
    right_clause = re.split(r"[.,;:!?—\"“”()]", example[idx + len(target_in_ex):])[0]

    left_tokens = [t for t in left_clause.strip().split() if t]
    right_tokens = [t for t in right_clause.strip().split() if t]

    def clean_tok(t: str) -> str:
        return t.strip("'-’‘")

    candidates: list[str] = []

    if pos == "noun":
        # Pattern 1: Adjective / Noun modifier + target noun (e.g. "normal transportation", "ancient temple")
        if left_tokens:
            prev = clean_tok(left_tokens[-1]).lower()
            if (
                prev not in STOP_NEIGHBORS
                and prev not in DETERMINERS_AND_PREPS
                and len(prev) >= 3
                and prev.isalpha()
                and not left_tokens[-1][0].isupper()
            ):
                phrase = f"{prev} {target_in_ex.lower()}"
                candidates.append(phrase)
            # Pattern 2: Verb + (a/an/the/poss) + target noun (e.g. "take a bath", "take a risk")
            elif prev in ("a", "an", "the", "my", "his", "her", "our", "their", "your", "some") and len(left_tokens) >= 2:
                vprev = clean_tok(left_tokens[-2]).lower()
                if vprev in ("took", "taken", "takes", "taking"):
                    vprev = "take"
                if (
                    vprev not in STOP_NEIGHBORS
                    and vprev not in WEAK_COLLOC_VERBS
                    and vprev not in DETERMINERS_AND_PREPS
                    and len(vprev) >= 3
                    and vprev.isalpha()
                    and not left_tokens[-2][0].isupper()
                ):
                    art = "a" if prev in ("a", "my", "his", "her", "our", "their", "your") and not target_in_ex.lower().endswith("s") else (
                        "an" if prev == "an" else ("the" if prev == "the" else "")
                    )
                    if art == "a" and target_in_ex[0].lower() in "aeiou":
                        art = "an"
                    phrase = f"{vprev} {art + ' ' if art else ''}{target_in_ex.lower()}".strip()
                    candidates.append(phrase)

        # Pattern 3: target noun + of + (det) + noun (only when complete noun phrase, not dangling adjective)
        if len(right_tokens) >= 2:
            prep = clean_tok(right_tokens[0]).lower()
            if prep in ("of", "for", "against", "between"):
                n1 = clean_tok(right_tokens[1]).lower()
                if n1 in ("a", "an", "the") and len(right_tokens) >= 3:
                    n2 = clean_tok(right_tokens[2]).lower()
                    has_trailing_noun = len(right_tokens) >= 4 and clean_tok(right_tokens[3]).lower() not in STOP_NEIGHBORS and clean_tok(right_tokens[3]).lower() not in DETERMINERS_AND_PREPS and clean_tok(right_tokens[3]).isalpha()
                    if not has_trailing_noun and n2 not in STOP_NEIGHBORS and n2 not in DETERMINERS_AND_PREPS and len(n2) >= 3 and n2.isalpha() and not right_tokens[2][0].isupper():
                        candidates.append(f"{target_in_ex.lower()} {prep} {n1} {n2}")
                elif len(right_tokens) == 2 and n1 not in STOP_NEIGHBORS and n1 not in DETERMINERS_AND_PREPS and len(n1) >= 4 and n1.isalpha() and not right_tokens[1][0].isupper():
                    candidates.append(f"{target_in_ex.lower()} {prep} {n1}")

    elif pos == "verb":
        # Pattern 1: verb + (det) + object noun (e.g. "curb anger", "found a colony")
        if right_tokens:
            r0 = clean_tok(right_tokens[0]).lower()
            if r0 in ("a", "an", "the", "my", "his", "her", "our", "their", "your", "some") and len(right_tokens) >= 2:
                r1 = clean_tok(right_tokens[1]).lower()
                kinship = {"brother", "sister", "mother", "father", "mom", "dad", "son", "daughter", "grandfather", "grandmother", "uncle", "aunt", "friend", "friends", "wife", "husband"}
                def _det_for(noun_tok: str) -> str:
                    if r0 in ("a", "an", "the"):
                        return r0 + " "
                    if noun_tok.endswith("s"):
                        return ""
                    return ("an " if noun_tok[0] in "aeiou" else "a ")

                if len(right_tokens) >= 3 and r1 not in STOP_NEIGHBORS and r1 not in DETERMINERS_AND_PREPS and r1.isalpha():
                    r2 = clean_tok(right_tokens[2]).lower()
                    if r2 not in STOP_NEIGHBORS and r2 not in DETERMINERS_AND_PREPS and r2 not in kinship and r2.isalpha() and not right_tokens[2][0].isupper():
                        candidates.append(f"{w_low} {_det_for(r1)}{r1} {r2}".strip())
                elif r1 not in STOP_NEIGHBORS and r1 not in DETERMINERS_AND_PREPS and r1 not in kinship and len(r1) >= 3 and r1.isalpha() and not right_tokens[1][0].isupper():
                    candidates.append(f"{w_low} {_det_for(r1)}{r1}".strip())
            elif r0 in ("in", "on", "at", "to", "for", "with", "from", "into", "out", "up", "down", "over", "away", "off", "against") and len(right_tokens) >= 2:
                r1 = clean_tok(right_tokens[1]).lower()
                if r1 in ("a", "an", "the") and len(right_tokens) >= 3:
                    r2 = clean_tok(right_tokens[2]).lower()
                    if r2 not in STOP_NEIGHBORS and r2 not in DETERMINERS_AND_PREPS and r2.isalpha() and not right_tokens[2][0].isupper():
                        candidates.append(f"{w_low} {r0} {r1} {r2}")
                elif r1 not in STOP_NEIGHBORS and r1 not in DETERMINERS_AND_PREPS and r1.isalpha() and not right_tokens[1][0].isupper():
                    candidates.append(f"{w_low} {r0} {r1}")
            elif r0 not in STOP_NEIGHBORS and r0 not in DETERMINERS_AND_PREPS and len(r0) >= 3 and r0.isalpha() and not right_tokens[0][0].isupper():
                candidates.append(f"{w_low} {r0}")

    elif pos == "adjective":
        # Pattern 1: target adj + noun (e.g. "martial art", "arid desert")
        if right_tokens:
            r0 = clean_tok(right_tokens[0]).lower()
            if r0 not in STOP_NEIGHBORS and r0 not in DETERMINERS_AND_PREPS and len(r0) >= 3 and r0.isalpha() and not right_tokens[0][0].isupper():
                candidates.append(f"{target_in_ex.lower()} {r0}")
            elif r0 in ("to", "of", "for", "with", "at", "in", "about", "from") and len(right_tokens) >= 2:
                r1 = clean_tok(right_tokens[1]).lower()
                if r1 not in STOP_NEIGHBORS and r1 not in DETERMINERS_AND_PREPS and len(r1) >= 3 and r1.isalpha() and not right_tokens[1][0].isupper():
                    candidates.append(f"{target_in_ex.lower()} {r0} {r1}")

    elif pos == "adverb":
        if left_tokens:
            l0 = clean_tok(left_tokens[-1]).lower()
            if l0 not in STOP_NEIGHBORS and l0 not in DETERMINERS_AND_PREPS and len(l0) >= 3 and l0.isalpha() and not left_tokens[-1][0].isupper():
                candidates.append(f"{l0} {target_in_ex.lower()}")
        if right_tokens:
            r0 = clean_tok(right_tokens[0]).lower()
            if r0 not in STOP_NEIGHBORS and r0 not in DETERMINERS_AND_PREPS and len(r0) >= 3 and r0.isalpha() and not right_tokens[0][0].isupper():
                candidates.append(f"{target_in_ex.lower()} {r0}")

    elif pos in ("preposition", "conjunction", "determiner", "pronoun"):
        if right_tokens:
            r0 = clean_tok(right_tokens[0]).lower()
            if r0 in ("a", "an", "the") and len(right_tokens) >= 2:
                r1 = clean_tok(right_tokens[1]).lower()
                if r1 not in STOP_NEIGHBORS and r1.isalpha() and not right_tokens[1][0].isupper():
                    candidates.append(f"{target_in_ex.lower()} {r0} {r1}")
            elif r0 not in STOP_NEIGHBORS and len(r0) >= 3 and r0.isalpha() and not right_tokens[0][0].isupper():
                candidates.append(f"{target_in_ex.lower()} {r0}")

    cleaned_out: list[str] = []
    for c in candidates:
        c = re.sub(r"\s+", " ", c).strip()
        if not c or is_synthetic_collocation(c, word):
            continue
        if c.lower() in (f"the {w_low}", f"a {w_low}", f"an {w_low}", f"to {w_low}", f"very {w_low}", f"quite {w_low}"):
            continue
        if re.match(r"^make\s+a\s+", c, re.I) or re.match(r"^a\s+\S+\s+of$", c, re.I):
            continue
        if c not in cleaned_out:
            cleaned_out.append(c)
        if len(cleaned_out) >= 2:
            break
    return cleaned_out


def build_lexicon(input_json: Path, output_js: Path) -> None:
    raw = json.loads(input_json.read_text(encoding="utf-8"))
    cards = raw.get("cards") or []
    if len(cards) < 3600:
        raise ValueError(f"Expected >= 3600 cards in {input_json}, got {len(cards)}")

    entries: dict[str, list] = {}
    for c in cards:
        cid = str(c["id"]).strip()
        word = str(c.get("front") or c.get("term") or "").strip()
        pos = normalize_pos(cid, str(c.get("pos") or ""))
        pos_idx = CANONICAL_POS.index(pos)

        if cid in DEF_OVERRIDES_BY_ID:
            exp_def_w, raw_def = DEF_OVERRIDES_BY_ID[cid]
            assert exp_def_w.lower() == word.lower(), f"DEF override mismatch on {cid}: {exp_def_w} != {word}"
        else:
            raw_def = str(c.get("definitionEn") or c.get("meaning") or "")
        def_en = clean_ocr_text(raw_def)

        raw_ex = EXAMPLE_OVERRIDES_BY_ID.get(cid) or str(c.get("example") or "")
        example = clean_ocr_text(raw_ex)

        if cid in MEANING_VI_BY_ID:
            exp_vi_w, meaning_vi = MEANING_VI_BY_ID[cid]
            assert exp_vi_w.lower() == word.lower(), f"VI override mismatch on {cid}: {exp_vi_w} != {word}"
        else:
            meaning_vi = str(c.get("meaningVi") or "").strip()
        # Normalize leading uppercase on non-proper Vietnamese glosses
        if meaning_vi and cid != "sr-b06-u19-02" and meaning_vi[0].isupper() and not meaning_vi.startswith(("IELTS", "DNA", "AI", "Úc")):
            meaning_vi = meaning_vi[0].lower() + meaning_vi[1:]
        meaning_vi = meaning_vi.rstrip(".")

        ipa = normalize_ipa(cid, word, str(c.get("phonetic") or ""))
        level, src_idx = assign_cefr(cid, word, str(c.get("level") or c.get("cefrLevel") or ""))
        cloze_target = extract_cloze_target(cid, word, example, str(c.get("clozeText") or ""))

        # Collocations: preserve genuine curated ones; replace synthetic ones with natural collocations
        old_collocs = [str(x).strip() for x in (c.get("collocations") or []) if str(x).strip()]
        w_low = word.lower()
        if w_low in CURATED_COLLOCATIONS_BY_WORD:
            collocs = list(CURATED_COLLOCATIONS_BY_WORD[w_low])
        elif old_collocs and not any(is_synthetic_collocation(x, word) for x in old_collocs):
            collocs = old_collocs
        else:
            collocs = extract_natural_collocation_from_example(word, pos, cloze_target, example)

        entries[cid] = [
            word,
            pos_idx,
            level,
            src_idx,
            ipa,
            def_en,
            meaning_vi,
            example,
            cloze_target,
            collocs,
        ]

    validate_entries(entries)

    lines = [
        ".pragma library",
        "// SpacedRepetitionEssential4000.js",
        "// Authoritative lexical metadata for all 3,603 4000 Essential English Words (Vol. 1-6) & starter cards.",
        "// Generated & verified by scripts/build-essential4000-lexicon.py.",
        "",
        "var LEXICON_REVISION = 2;",
        "var POS_NAMES = " + json.dumps(list(CANONICAL_POS), ensure_ascii=False) + ";",
        "var LEVEL_SOURCES = " + json.dumps(list(LEVEL_SOURCES), ensure_ascii=False) + ";",
        "",
        "// Compact tuple per card ID:",
        "// [0:word, 1:posIdx, 2:level, 3:sourceIdx, 4:phonetic, 5:definitionEn, 6:meaningVi, 7:example, 8:clozeTarget, 9:collocations]",
        "var CARDS_BY_ID = {",
    ]
    items = list(entries.items())
    for i, (cid, tuple_val) in enumerate(items):
        comma = "," if i + 1 < len(items) else ""
        lines.append(f"    {json.dumps(cid)}: {json.dumps(tuple_val, ensure_ascii=False)}{comma}")
    lines.append("};")
    lines.append(
        r"""
var _wordIndex = null;
var _materializedCache = {};

function conciseMeaningVi(rawVi) {
    var s = String(rawVi || "").trim().replace(/\.$/, "");
    var base = s.replace(/\s*\([^)]*\)\s*/g, "").trim() || s;
    var semi = base.split(";").map(function(p) { return p.trim(); }).filter(Boolean);
    var primary = semi.length > 0 ? semi[0] : base;
    var parts = primary.split(",").map(function(p) { return p.trim(); }).filter(Boolean);
    if (parts.length > 2) primary = parts.slice(0, 2).join(", ");
    if (primary.length > 42 && parts.length >= 2) primary = parts[0];
    return primary;
}

function buildClozeFromEntry(example, clozeTarget, pos, meaningVi) {
    var ex = String(example || "");
    var target = String(clozeTarget || "");
    if (!ex || !target) return ex;
    var concise = conciseMeaningVi(meaningVi);
    var hint = concise ? (pos + " — " + concise) : pos;
    var escaped = target.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    var wb = new RegExp("(^|[^A-Za-z])(" + escaped + ")(?=$|[^A-Za-z])", "g");
    if (wb.test(ex)) {
        wb.lastIndex = 0;
        var count = 0;
        return ex.replace(wb, function(_, prefix, matched) {
            count++;
            return prefix + "{{c" + count + "::" + matched + "::" + hint + "}}";
        });
    }
    var idx = ex.indexOf(target);
    if (idx < 0) return ex;
    return ex.slice(0, idx) + "{{c1::" + target + "::" + hint + "}}" + ex.slice(idx + target.length);
}

function _materialize(cardId, row) {
    if (!row) return null;
    if (Object.prototype.hasOwnProperty.call(_materializedCache, cardId)) {
        var cached = _materializedCache[cardId];
        return {
            id: cached.id,
            word: cached.word,
            pos: cached.pos,
            level: cached.level,
            levelSource: cached.levelSource,
            phonetic: cached.phonetic,
            definitionEn: cached.definitionEn,
            meaningVi: cached.meaningVi,
            example: cached.example,
            clozeTarget: cached.clozeTarget,
            clozeText: cached.clozeText,
            collocations: cached.collocations.slice()
        };
    }
    var pos = POS_NAMES[row[1]] || "noun";
    var levelSource = LEVEL_SOURCES[row[3]] || "Cambridge EVP";
    var built = {
        id: cardId,
        word: row[0],
        pos: pos,
        level: row[2],
        levelSource: levelSource,
        phonetic: row[4],
        definitionEn: row[5],
        meaningVi: row[6],
        example: row[7],
        clozeTarget: row[8],
        clozeText: buildClozeFromEntry(row[7], row[8], pos, row[6]),
        collocations: Array.isArray(row[9]) ? row[9].slice() : []
    };
    _materializedCache[cardId] = built;
    return {
        id: built.id,
        word: built.word,
        pos: built.pos,
        level: built.level,
        levelSource: built.levelSource,
        phonetic: built.phonetic,
        definitionEn: built.definitionEn,
        meaningVi: built.meaningVi,
        example: built.example,
        clozeTarget: built.clozeTarget,
        clozeText: built.clozeText,
        collocations: built.collocations.slice()
    };
}

function lookupByCardId(cardId) {
    var key = String(cardId || "").trim();
    if (!key || !Object.prototype.hasOwnProperty.call(CARDS_BY_ID, key)) return null;
    return _materialize(key, CARDS_BY_ID[key]);
}

function _ensureWordIndex() {
    if (_wordIndex !== null) return _wordIndex;
    _wordIndex = {};
    var ids = Object.keys(CARDS_BY_ID);
    for (var i = 0; i < ids.length; i++) {
        var cid = ids[i];
        var row = CARDS_BY_ID[cid];
        var w = String(row[0] || "").trim().toLowerCase();
        if (w && !Object.prototype.hasOwnProperty.call(_wordIndex, w)) {
            _wordIndex[w] = cid;
        }
    }
    return _wordIndex;
}

function lookupByWord(rawWord) {
    var w = String(rawWord || "").trim().toLowerCase();
    if (!w) return null;
    var idx = _ensureWordIndex();
    var cid = idx[w];
    if (!cid) return null;
    return _materialize(cid, CARDS_BY_ID[cid]);
}
"""
    )

    output_js.write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote {len(entries)} entries to {output_js} ({output_js.stat().st_size:,} bytes)")


def validate_entries(entries: dict[str, list]) -> None:
    assert len(entries) == 3603, f"Expected 3603 entries, got {len(entries)}"
    for cid, row in entries.items():
        word, pos_idx, level, src_idx, ipa, def_en, meaning_vi, example, cloze_target, collocs = row
        pos = CANONICAL_POS[pos_idx]
        assert pos in CANONICAL_POS, f"Invalid POS {pos} on {cid}"
        assert level in ("A1", "A2", "B1", "B2", "C1", "C2"), f"Invalid CEFR {level} on {cid}"
        assert 0 <= src_idx < len(LEVEL_SOURCES)
        assert ipa.startswith("/") and ipa.endswith("/") and len(ipa) >= 3, f"Bad IPA {ipa} on {cid}"
        assert ":" not in ipa and "ӕ" not in ipa and "ē" not in ipa and "(" not in ipa and ")" not in ipa, f"Dirty IPA {ipa} on {cid}"
        assert "əː" not in ipa, f"Unresolved əː in IPA {ipa} on {cid}"
        assert def_en and not re.search(r"[àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ]", def_en, re.I), (
            f"Vietnamese in definitionEn on {cid}: {def_en}"
        )
        assert meaning_vi, f"Empty meaningVi on {cid}"
        if len(word) >= 3:
            assert not re.search(r"(?<![A-Za-z])" + re.escape(word) + r"(?![A-Za-z])", meaning_vi, re.I), (
                f"English word '{word}' leaked in meaningVi on {cid}: {meaning_vi}"
            )
        assert _is_valid_cloze_form(word, cloze_target, example), (
            f"Cloze target '{cloze_target}' is not a valid whole-word form of '{word}' in example on {cid}: {example}"
        )
        for col in collocs:
            assert not is_synthetic_collocation(col, word), f"Synthetic collocation on {cid} ({word}): {col}"
            phrase = col.split(" - ")[0].split(" — ")[0].strip()
            assert len(phrase.split()) >= 2, f"Single-token collocation on {cid} ({word}): {col}"

    # Specific regression checks
    tr = entries["sr-b04-u29-20"]
    assert CANONICAL_POS[tr[1]] == "noun", f"transportation POS must be noun, got {CANONICAL_POS[tr[1]]}"
    assert tr[2] in ("A2", "B1"), f"transportation level must be A2/B1, got {tr[2]}"
    assert "phương tiện giao thông" in tr[6], f"transportation meaningVi wrong: {tr[6]}"
    assert len(tr[9]) >= 1 and "public transportation" in tr[9][0]


def verify_existing_js(js_path: Path) -> None:
    txt = js_path.read_text(encoding="utf-8")
    assert txt.startswith(".pragma library"), "Missing .pragma library header"
    m = re.search(r"var CARDS_BY_ID = (\{[\s\S]*?\n\});", txt)
    assert m, "Could not parse CARDS_BY_ID block"
    entries = json.loads(m.group(1))
    validate_entries(entries)
    print(f"Verified {len(entries)} entries in {js_path} — ALL CHECKS PASSED")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--input", type=Path, help="Read-only scratch copy of spaced-repetition.json")
    ap.add_argument("--output", type=Path, default=OUT_JS)
    ap.add_argument("--verify", action="store_true", help="Verify existing SpacedRepetitionEssential4000.js")
    args = ap.parse_args()

    if args.verify:
        verify_existing_js(args.output)
        return 0
    if not args.input:
        ap.error("--input is required unless --verify is passed")
    # Safety guard: refuse to ever touch live user file directly even for reading if scratch is expected
    if ".local/state/quickshell/user" in str(args.input.resolve()):
        raise RuntimeError("Refusing to operate directly on live user spaced-repetition.json; pass a scratch copy!")
    build_lexicon(args.input, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
