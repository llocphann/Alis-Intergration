#!/usr/bin/env python3
"""Idempotent Agenda link mutation in an existing, explicitly configured task note."""
import argparse
import fcntl
import hashlib
import json
import os
import stat
import sys

import agenda_metadata as metadata
import obsidian_daily_todo as daily
import obsidian_todo as core


def mutate(source, event, operation='ensure'):
    link = event.get('todoLink', event)
    key = link.get('key', '')
    if link.get('version') != 1 or not isinstance(key, str) or not metadata.KEY.fullmatch(key):
        raise core.TodoError('invalid_agenda_link', 'Unsupported Agenda task identity')
    mode = source.get('mode', 'daily')
    def load():
        if mode == 'managed':
            return core._load_document(source['vault'], source['note'])
        return daily._load_document(source['vault'], source.get('folder',daily.DEFAULT_FOLDER),
            source.get('fmt',daily.DEFAULT_FORMAT),source.get('day'),source.get('heading',daily.DEFAULT_HEADING),
            source.get('heading_level',2))
    first = load()
    # Serialize cooperating Agenda workers across inode replacement. Ordinary
    # external edits are independently checked against the original bytes.
    descriptor = os.open(first['resolved'].parent, os.O_RDONLY | getattr(os,'O_DIRECTORY',0))
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX)
        doc = load()
        lines = list(doc['lines'])
        matches = []
        for index in range(doc['startIndex']+1, doc['endIndex']):
            if not doc['outside'][index]:
                continue
            raw = lines[index].rstrip('\r\n')
            task = core._TASK_RE.match(raw)
            if not task:
                continue
            body, info = metadata.split(task.group(4))
            if info and info['key'] == key:
                matches.append((index,task,body,info))
        if len(matches)>1:
            raise core.TodoError('ambiguous_agenda_link','More than one task has this Agenda identity')
        receipt = {'key':key,'kind':operation,'fingerprint':event.get('agendaFingerprint',''),'taskMissing':False}
        if operation == 'delete':
            if matches:del lines[matches[0][0]]
        elif operation == 'unlink':
            if matches:
                index,task,body,_ = matches[0]
                ending = lines[index][len(lines[index].rstrip('\r\n')):]
                lines[index] = task.string[:task.start(4)] + body + ending
        else:
            fields = event.get('agendaDesired')
            fingerprint = event.get('agendaFingerprint','')
            if not isinstance(fields,dict) or json.loads(fingerprint) != fields:
                raise core.TodoError('invalid_agenda_fields','Agenda owned fields do not match their revision')
            template = daily._format_task_text(fields['content'],fields['startTime'],fields['endTime'])
            info = {'version':1,'key':key,'eventId':event.get('id'),'owned':template,
                'title':fields['content'],'date':fields['date'],'startTime':fields['startTime'],
                'endTime':fields['endTime'],'sourceDate':link.get('sourceDate',''),
                'fingerprintHash':hashlib.sha256(fingerprint.encode()).hexdigest()}
            if matches:
                index,task,body,old = matches[0]
                previous = str(old.get('owned',''))
                if body == previous:
                    body = template
                elif previous and body.startswith(previous+' '):
                    body = template + body[len(previous):]
                else:
                    receipt['preservedUserText']=True
                ending = lines[index][len(lines[index].rstrip('\r\n')):]
                lines[index] = task.string[:task.start(4)] + body + metadata.render(info) + ending
            elif link.get('state') == 'linked':
                receipt['taskMissing']=True  # A deleted task is never recreated.
            else:
                index = daily._insertion_index(doc,fields['startTime']) if mode=='daily' else doc['endIndex']
                lines.insert(index,'- [ ] '+template+metadata.render(info)+daily._preferred_newline(doc))
        raw = core._encode_document(doc,lines)
        if raw != doc['raw']:
            if not stat.S_IMODE(doc['resolved'].stat().st_mode) & 0o222:
                raise core.TodoError('note_read_only','Task note is read-only')
            core._atomic_replace_if_unchanged(doc,raw)
        payload = core._scan_payload(load()) if mode=='managed' else daily._scan_payload(load(),source.get('default_duration',30))
        payload['agendaReceipt']=receipt
        return payload
    finally:
        fcntl.flock(descriptor,fcntl.LOCK_UN)
        os.close(descriptor)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--mode',choices=['daily','managed'],required=True)
    parser.add_argument('--operation',choices=['ensure','unlink','delete'],default='ensure')
    parser.add_argument('--vault',required=True)
    parser.add_argument('--note',default='Hadalis/Todo.md')
    parser.add_argument('--folder',default=daily.DEFAULT_FOLDER)
    parser.add_argument('--format',dest='fmt',default=daily.DEFAULT_FORMAT)
    parser.add_argument('--date',dest='day',default='')
    parser.add_argument('--heading',default=daily.DEFAULT_HEADING)
    parser.add_argument('--heading-level',type=int,default=2)
    parser.add_argument('--default-duration',type=int,default=30)
    parser.add_argument('--event',required=True)
    args=vars(parser.parse_args())
    try:
        text=args.pop('event')
        if len(text.encode())>96000:
            raise core.TodoError('agenda_payload_too_large','Agenda task update exceeds its bounded input size')
        payload=mutate(args,json.loads(text),args.pop('operation'))
        print(json.dumps(payload,ensure_ascii=False));return 0
    except (core.TodoError,ValueError,KeyError,TypeError) as error:
        print(json.dumps({'ok':False,'error':{'code':getattr(error,'code','invalid_agenda_update'),'message':str(error)}}));return 1


if __name__=='__main__':
    sys.exit(main())
