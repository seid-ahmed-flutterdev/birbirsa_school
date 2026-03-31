"""Test: send multi-photo search result + new registration notification."""
import os, sys, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from search_bot import read_registrations, _send_student_result, bot, MEDIA_DIR

CHAT_ID = '8319751158'

regs = read_registrations()

# Find a student with MULTIPLE photos  
multi_photo = [r for r in regs if r.get('photo') and ',' in r.get('photo', '')]
single_photo = [r for r in regs if r.get('photo') and ',' not in r.get('photo', '')]

print(f'Records with multi-photos: {len(multi_photo)}')
print(f'Records with single photo: {len(single_photo)}')

# Test multi-photo
if multi_photo:
    r = multi_photo[0]
    print(f'\n--- MULTI-PHOTO TEST ---')
    print(f'Name: {r["name"]}, Photos: {r["photo"]}')
    _send_student_result(CHAT_ID, r)
    print('Multi-photo sent! Check Telegram.')

# Test single photo  
if single_photo:
    r = single_photo[0]
    print(f'\n--- SINGLE PHOTO TEST ---')
    print(f'Name: {r["name"]}, Photo: {r["photo"]}')
    _send_student_result(CHAT_ID, r)
    print('Single photo sent! Check Telegram.')

# Test no-photo record
no_photo = [r for r in regs if not r.get('photo')]
if no_photo:
    r = no_photo[0]
    print(f'\n--- TEXT-ONLY TEST ---')
    print(f'Name: {r["name"]}')
    _send_student_result(CHAT_ID, r)
    print('Text-only sent! Check Telegram.')

print('\n=== ALL TESTS DONE ===')
