#!/usr/bin/env python3
"""Real note CAS, idempotence, metadata interoperability and concurrent workers."""
import codecs,json,os,subprocess,sys,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parent/'todo'))
import obsidian_agenda as agenda
import agenda_metadata as metadata
import obsidian_todo as core

class AgendaTests(unittest.TestCase):
    def fixture(self,mode='daily',newline='\n',bom=False):
        temp=tempfile.TemporaryDirectory();self.addCleanup(temp.cleanup)
        vault=Path(temp.name)/'Vault';vault.mkdir();file=vault/'Tasks.md'
        body=('# Before\nPrivate text\n'+('## Tasks\n' if mode=='daily' else core.START_MARKER+'\n')+
              '- [x] Existing\n  Independent notes\n'+('## Journal\n' if mode=='daily' else core.END_MARKER+'\n')+'Untouched\n')
        file.write_bytes((codecs.BOM_UTF8 if bom else b'')+body.replace('\n',newline).encode())
        source={'mode':mode,'vault':str(vault),'folder':'','fmt':'Tasks.md','note':'Tasks.md','day':'2026-10-12','heading':'Tasks','heading_level':2}
        return source,file
    def event(self,key='agenda-fixture-001',state='pending',title='Review'):
        fields={'content':title,'description':'Event details','date':'2026-10-13','startTime':'09:00','endTime':'10:00','startDate':'2026-10-13T02:00:00Z','endDate':'2026-10-13T03:00:00Z','allDay':False}
        return {'id':1,'todoLink':{'version':1,'key':key,'state':state,'sourceDate':'2026-10-12'},'agendaDesired':fields,'agendaFingerprint':json.dumps(fields,separators=(',',':'))}
    def test_idempotent_update_and_unlink_both_modes_bom_crlf(self):
        for mode in ['daily','managed']:
            for newline,bom in [('\n',False),('\r\n',True)]:
                with self.subTest(mode=mode,newline=newline,bom=bom):
                    source,file=self.fixture(mode,newline,bom);original=file.read_bytes();event=self.event()
                    first=agenda.mutate(source,event);one=file.read_bytes();self.assertEqual(len(first['tasks']),2)
                    self.assertEqual(agenda.mutate(source,event)['agendaReceipt']['key'],event['todoLink']['key']);self.assertEqual(file.read_bytes(),one)
                    self.assertEqual(first['tasks'][-1]['content'],'Review');self.assertEqual(first['tasks'][-1]['agenda']['key'],event['todoLink']['key'])
                    # The normal backend can toggle this linked checkbox, preserving metadata.
                    task=first['tasks'][-1]
                    if mode=='managed':core.toggle_basic_task(source['vault'],'Tasks.md',task['id'],first['document']['sha256'])
                    else:agenda.daily.toggle_task(source['vault'],'','Tasks.md',source['day'],'Tasks',2,30,task['id'],first['document']['sha256'])
                    updated=agenda.mutate(source,self.event(state='linked',title='Changed'));linked=next(item for item in updated['tasks'] if item.get('agenda'))
                    self.assertTrue(linked['done']);self.assertEqual(linked['content'],'Changed')
                    result=agenda.mutate(source,event['todoLink'],'unlink');self.assertEqual(len(result['tasks']),2);self.assertFalse(any(item.get('agenda') for item in result['tasks']))
                    final=file.read_bytes();self.assertEqual(final.startswith(codecs.BOM_UTF8),bom)
                    self.assertIn('Independent notes'.encode(),final);self.assertIn('Untouched'.encode(),final)
                    self.assertEqual(final.count(b'\n')-final.count(b'\r\n'),0 if newline=='\r\n' else final.count(b'\n'))
                    self.assertTrue(original.split(b'Private text')[0] in final)
    def test_deleted_linked_task_is_never_recreated(self):
        source,file=self.fixture();agenda.mutate(source,self.event());raw=file.read_text();file.write_text('\n'.join(line for line in raw.split('\n') if 'alis:agenda:v1:' not in line))
        before=file.read_bytes();result=agenda.mutate(source,self.event(state='linked',title='Changed'))
        self.assertTrue(result['agendaReceipt']['taskMissing']);self.assertEqual(file.read_bytes(),before)
    def test_explicit_delete_is_idempotent_and_keeps_independent_lines(self):
        for mode in ['daily','managed']:
            with self.subTest(mode=mode):
                source,file=self.fixture(mode);event=self.event();agenda.mutate(source,event)
                file.write_text(file.read_text().replace('## Journal','  Linked child note\n## Journal') if mode=='daily' else file.read_text().replace(core.END_MARKER,'  Linked child note\n'+core.END_MARKER))
                result=agenda.mutate(source,event['todoLink'],'delete')
                self.assertFalse(any(item.get('agenda') for item in result['tasks']))
                self.assertEqual(len(result['tasks']),1)
                self.assertIn('Linked child note',file.read_text());self.assertIn('Independent notes',file.read_text())
                before=file.read_bytes();agenda.mutate(source,event['todoLink'],'delete')
                self.assertEqual(file.read_bytes(),before)
    def test_external_inline_and_child_notes_survive(self):
        source,file=self.fixture();agenda.mutate(source,self.event());text=file.read_text().replace('09:00 - 10:00 Review','09:00 - 10:00 Review extra #tag');file.write_text(text)
        result=agenda.mutate(source,self.event(state='linked',title='Renamed'))
        self.assertIn('Renamed extra #tag',file.read_text());self.assertIn('Independent notes',file.read_text())
        file.write_text(file.read_text().replace('Renamed extra #tag','User replaced title'))
        result=agenda.mutate(source,self.event(state='linked',title='Another title'))
        self.assertTrue(result['agendaReceipt']['preservedUserText']);self.assertIn('User replaced title',file.read_text())
    def test_ambiguous_identity_fails_unchanged_and_fences_are_ignored(self):
        source,file=self.fixture();agenda.mutate(source,self.event());line=next(line for line in file.read_text().splitlines() if 'alis:agenda:v1:' in line)
        file.write_text(file.read_text().replace('## Journal','~~~\n'+line+'\n~~~\n## Journal'));agenda.mutate(source,self.event())
        file.write_text(file.read_text().replace('## Journal',line+'\n## Journal'));before=file.read_bytes()
        with self.assertRaises(core.TodoError) as error:agenda.mutate(source,self.event())
        self.assertEqual(error.exception.code,'ambiguous_agenda_link');self.assertEqual(file.read_bytes(),before)
    def test_read_only_and_invalid_source_never_create_or_modify(self):
        source,file=self.fixture();file.chmod(0o400);before=file.read_bytes()
        with self.assertRaises(core.TodoError):agenda.mutate(source,self.event())
        self.assertEqual(file.read_bytes(),before);file.chmod(0o600)
        with self.assertRaises(core.TodoError):agenda.mutate(dict(source,fmt='../outside.md'),self.event())
        with self.assertRaises(core.TodoError):agenda.mutate(dict(source,fmt='Missing.md'),self.event())
        self.assertFalse((file.parent/'Missing.md').exists())
    def test_external_edit_between_read_and_write_is_preserved(self):
        source,file=self.fixture();original=core._atomic_replace_if_unchanged
        def conflict(doc,raw):file.write_bytes(file.read_bytes()+b'External change\n');original(doc,raw)
        with patch.object(core,'_atomic_replace_if_unchanged',conflict):
            with self.assertRaises(core.TodoError) as error:agenda.mutate(source,self.event())
        self.assertEqual(error.exception.code,'conflict');self.assertTrue(file.read_bytes().endswith(b'External change\n'));self.assertNotIn(b'alis:agenda:v1:',file.read_bytes())
    def test_concurrent_restarts_do_not_duplicate_or_lose_occurrences(self):
        source,file=self.fixture()
        base=[sys.executable,str(Path(agenda.__file__)),'--mode','daily','--vault',source['vault'],'--folder','','--format','Tasks.md','--date',source['day']]
        processes=[subprocess.Popen(base+['--event',json.dumps(self.event(key))],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True) for key in ['agenda-fixture-001','agenda-fixture-002','agenda-fixture-001']]
        for process in processes:
            out,err=process.communicate(timeout=8);self.assertEqual(process.returncode,0,(out,err));self.assertTrue(json.loads(out)['ok'])
        result=agenda.mutate(source,self.event());self.assertEqual(len(result['tasks']),3)
        self.assertEqual(len({item['agenda']['key'] for item in result['tasks'] if item.get('agenda')}),2)
    def test_untrusted_markers_remain_literal(self):
        for raw in ['ordinary <!-- alis:agenda:v1:bad -->','title <!-- other:marker -->']:
            self.assertEqual(metadata.split(raw),(raw,None))

if __name__=='__main__':unittest.main()
