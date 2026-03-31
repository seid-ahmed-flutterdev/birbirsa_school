import requests

# Simulate the web app calling server.py directly
res = requests.post('http://localhost:3000/api/notify-registration', json={
    'name': 'Python Test',
    'phone': '09121212',
    'reg_id': 'BR999999',
    'details': '🎯 NEW REGISTRATION\n\n🆔 ID: BR999999\n👤 Student: Python Test\n📞 Phone: 09121212',
    'type': 'registration'
})
print("No-photo test:", res.status_code, res.text)

# Now a test with an actual photo
with open('media/seid_1774015193_0.jpg', 'rb') as f:
    res = requests.post('http://localhost:3000/api/notify-registration', data={
        'name': 'Photo Test',
        'phone': '12345',
        'reg_id': 'BR88888',
        'details': '🎯 NEW REGISTRATION\n\n🆔 ID: BR88888\n👤 Student: Photo Test',
        'type': 'registration'
    }, files={'photos': ('test.jpg', f, 'image/jpeg')})
print("Photo test:", res.status_code, res.text)
