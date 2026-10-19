#!/usr/bin/env python3
"""Real filesystem contracts for the owned Obsidian color snippet."""
import colorsys,importlib.util,json,re,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location("obsidian_theme",ROOT/"scripts/integrations/obsidian_theme.py");theme=importlib.util.module_from_spec(spec);spec.loader.exec_module(theme)
class ThemeTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory(prefix="alis-obsidian-theme-");self.addCleanup(self.tmp.cleanup)
  self.vault=Path(self.tmp.name)/"Vault có spaces";self.cfg=self.vault/"custom-config";self.cfg.mkdir(parents=True)
  self.appearance=self.cfg/"appearance.json";self.original={"cssTheme":"Border","enabledCssSnippets":["01_Core","custom"],"accentColor":"#3e5865","fonts":{"interface":"GeistMono"},"future":{"keep":True}}
  self.appearance.write_text(json.dumps(self.original,ensure_ascii=False));self.appearance.chmod(0o640)
  self.request={"vaultPath":str(self.vault),"configPath":"custom-config","palette":{"background":"#10181b","foreground":"#e6edef","accent":"#a0cddf"}}
 def execute(self,action):return theme.execute({**self.request,"action":action})
 def test_inspection_is_read_only(self):
  before=self.appearance.read_bytes();info=self.execute("inspect");self.assertEqual(info["activeTheme"],"Border");self.assertEqual(self.appearance.read_bytes(),before);self.assertFalse((self.cfg/"snippets").exists())
 def test_apply_preserves_theme_and_other_preferences(self):
  result=self.execute("apply");data=json.loads(self.appearance.read_text());self.assertEqual(data,{**self.original,"enabledCssSnippets":["01_Core","custom",theme.SNIPPET]});self.assertTrue(result["enabled"]);self.assertEqual(self.appearance.stat().st_mode&0o777,0o640)
 def test_idempotence_has_no_rewrite(self):
  self.execute("apply");css=self.cfg/"snippets"/(theme.SNIPPET+".css");times=(css.stat().st_mtime_ns,self.appearance.stat().st_mtime_ns);result=self.execute("apply");self.assertFalse(result["changed"]);self.assertEqual((css.stat().st_mtime_ns,self.appearance.stat().st_mtime_ns),times)
 def test_palette_changes_only_owned_css(self):
  self.execute("apply");before=self.appearance.read_bytes();self.request["palette"]["accent"]="#dca0df";self.assertTrue(self.execute("apply")["changed"]);self.assertEqual(self.appearance.read_bytes(),before)
 def test_restore_preserves_concurrent_preferences(self):
  self.execute("apply");value=json.loads(self.appearance.read_text());value["newPreference"]="kept";value["enabledCssSnippets"].append("after");self.appearance.write_text(json.dumps(value));self.execute("disable");value["enabledCssSnippets"].remove(theme.SNIPPET);self.assertEqual(json.loads(self.appearance.read_text()),value)
 def test_invalid_palette_cannot_modify_files(self):
  before=self.appearance.read_bytes();self.request["palette"]["accent"]="red; display:none";self.assertRaises(ValueError,self.execute,"apply");self.assertEqual(self.appearance.read_bytes(),before);self.assertFalse((self.cfg/"snippets").exists())
 def test_detect_open_vault_and_custom_folder(self):
  app=Path(self.tmp.name)/"app";app.mkdir();(app/"obsidian.json").write_text(json.dumps({"vaults":{"one":{"path":"/not/open"},"two":{"path":str(self.vault),"open":True}}}));self.request.pop("vaultPath");self.request["applicationConfigPath"]=str(app);self.assertEqual(self.execute("inspect")["vaultPath"],str(self.vault))
 def test_unknown_paths_do_not_create_config(self):
  self.request["configPath"]="wrong-folder";self.assertRaises(ValueError,self.execute,"apply");self.assertFalse((self.vault/"wrong-folder").exists())
 def test_shell_is_only_palette_owner(self):
  snippets=self.cfg/"snippets";snippets.mkdir();(snippets/"01_Core.css").write_text(':root { --cc-p00: #ffffff; --cc-p13: #000000; }')
  stops,profile=theme.weights(self.cfg,self.original);self.assertEqual(profile,"Alis palette");self.assertEqual(stops,theme.WEIGHTS)
 def test_dark_and_light_colors_are_bounded(self):
  for background,foreground in [("#10181b","#e6edef"),("#f4f7f8","#10181b")]:
   self.request["palette"].update(background=background,foreground=foreground);css=theme.make_css(self.request["palette"],theme.WEIGHTS)
   ramp=dict(re.findall(r'--cc-p(\d{2}):\s*(#[0-9a-f]{6})\s*!important;',css))
   self.assertEqual(set(ramp),{f'{i:02}' for i in range(14)})
   self.assertEqual(ramp['00'],min((background,foreground),key=lambda x:colorsys.rgb_to_hls(*theme.rgb(x))[1]))
   lightness=[colorsys.rgb_to_hls(*theme.rgb(ramp[f'{i:02}']))[1] for i in range(14)]
   self.assertTrue(all(a<=b for a,b in zip(lightness,lightness[1:])))
 def test_white_ink_softens_without_moving_screen_edge_background(self):
  css=theme.make_css({'background':'#0c1113','foreground':'#ffffff','accent':'#8dcff1'},theme.WEIGHTS)
  ramp=dict(re.findall(r'--cc-p(\d{2}):\s*(#[0-9a-f]{6})\s*!important;',css));self.assertEqual(ramp['00'],'#0c1113');self.assertNotEqual(ramp['13'],'#ffffff')
 def test_migrate_owned_hadalis_selection_and_keep_its_bytes(self):
  snippets=self.cfg/'snippets';snippets.mkdir();legacy=snippets/(theme.LEGACY_SNIPPET+'.css');legacy.write_text('/* Generated by Hadalis. Old colors */')
  before=legacy.read_bytes();value={**self.original,'enabledCssSnippets':['01_Core',theme.LEGACY_SNIPPET,'custom']};self.appearance.write_text(json.dumps(value))
  self.execute('apply');self.assertEqual(json.loads(self.appearance.read_text())['enabledCssSnippets'],['01_Core','custom',theme.SNIPPET]);self.assertEqual(legacy.read_bytes(),before)
  self.execute('disable');self.assertEqual(json.loads(self.appearance.read_text())['enabledCssSnippets'],['01_Core','custom'])
 def test_unowned_legacy_and_new_names_are_preserved(self):
  snippets=self.cfg/'snippets';snippets.mkdir();legacy=snippets/(theme.LEGACY_SNIPPET+'.css');legacy.write_text('/* User CSS */')
  self.original['enabledCssSnippets'].append(theme.LEGACY_SNIPPET);self.appearance.write_text(json.dumps(self.original));self.execute('apply')
  self.assertIn(theme.LEGACY_SNIPPET,json.loads(self.appearance.read_text())['enabledCssSnippets'])
  new=snippets/(theme.SNIPPET+'.css');new.write_text('/* user-owned destination */');before=self.appearance.read_bytes();self.assertRaises(ValueError,self.execute,'apply');self.assertEqual(new.read_text(),'/* user-owned destination */');self.assertEqual(self.appearance.read_bytes(),before)
 def test_numeric_accent_and_status_channels_follow_both_modes(self):
  css=theme.make_css(self.request['palette'],theme.WEIGHTS)
  self.assertEqual(css.count('--accent-h:'),2);self.assertEqual(css.count('--color-accent-rgb:'),2)
  self.assertEqual(css.count('--color-green-rgb:'),2);self.assertIn('--text-normal: var(--av-ui-text) !important;',css)
  self.assertNotIn('--av-theme-sync:',css);self.assertNotIn('av-palette-alis',css)
 def test_reference_vaults_use_only_owned_snippet(self):
  # Appearance layouts and cc stops read from Abyssal-Vault / Obsidian-Vault.
  # Exercise copies, never the maintainer's live notes/configuration.
  stops=['0a0e10','0c1113','10181b','162024','1d2a2f','26363e','30464f','3e5965','4e707e','5f899b','7da0b0','a0bac5','c6d6dc','e6edef']
  for name,extra in [('Abyssal-Vault',[]),('Obsidian-Vault',['01_Core_System','02_Homepage','03_Bases','04_Content_Interface_And_Plugins','05_Style_Setting'])]:
   with self.subTest(vault=name):
    vault=Path(self.tmp.name)/name;cfg=vault/'.obsidian';cfg.mkdir(parents=True)
    appearance={'cssTheme':'Border','enabledCssSnippets':extra+['01_Core','02_Components','03_Compatibility','04_Configuration'],'interfaceFontFamily':'GeistMono Nerd Font','textFontFamily':'GeistMono Nerd Font','monospaceFontFamily':'GeistMono Nerd Font'}
    (cfg/'appearance.json').write_text(json.dumps(appearance))
    theme_file=cfg/'themes/Border/theme.css';theme_file.parent.mkdir(parents=True);theme_file.write_text('body { --background-primary: #123456; }')
    snippets=cfg/'snippets';snippets.mkdir()
    for snippet in appearance['enabledCssSnippets']:(snippets/(snippet+'.css')).write_text('/* preserved user snippet */')
    (snippets/'01_Core.css').write_text(':root {'+''.join(f'--cc-p{i:02}: #{color};' for i,color in enumerate(stops))+'}')
    before={str(p.relative_to(cfg)):p.read_bytes() for p in cfg.rglob('*') if p.is_file() and p.name!='appearance.json'}
    request={'vaultPath':str(vault),'palette':self.request['palette']}
    info=theme.execute(request);self.assertEqual(info['profile'],'Alis palette');self.assertEqual(info['snippetPath'],str(snippets/(theme.SNIPPET+'.css')))
    theme.execute({**request,'action':'apply'})
    self.assertEqual(json.loads((cfg/'appearance.json').read_text()),{**appearance,'enabledCssSnippets':appearance['enabledCssSnippets']+[theme.SNIPPET]})
    self.assertEqual({str(p.relative_to(cfg)):p.read_bytes() for p in cfg.rglob('*') if p.is_file() and str(p.relative_to(cfg)) in before},before)
    theme.execute({**request,'action':'disable'});self.assertEqual(json.loads((cfg/'appearance.json').read_text()),appearance)
if __name__=="__main__":unittest.main()
