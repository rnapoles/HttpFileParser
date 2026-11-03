baseUrl='http://localhost:8443'
apiUrl='http://localhost:8443/api/v1'
authToken=''
refreshToken=''
sessionId=''
csrfToken=''
userId='{{createUser.response.body.$.payload.id}}'
certificateId='{{createCertificate.response.body.$.payload.id}}'
eventId='{{listAuditEvents.response.body.$.payload.items[0].id}}'
publicOrigin='https://localhost:8443'
contentType='application/json'
mergePatch='application/merge-patch+json'
login='root'
password='+/Itu+II7VQLni8Z'
otpCode='437499'

# loginRequest
curl \
  -X POST \
  "${apiUrl}"'/auth/login' \
  -H 'Content-Type: '"${contentType}" \
  --data-raw '{
  "login": "'"${login}"'",
  "password": "'"${password}"'",
  "otpCode": "'"${otpCode}"'",
  "deviceName": "REST Client",
  "tokenDelivery": "body"
}'

# loginCookie
curl \
  -X POST \
  "${apiUrl}"'/auth/login' \
  -H 'Content-Type: '"${contentType}" \
  -H 'Origin: '"${publicOrigin}" \
  --data-raw '{
  "login": "'"${login}"'",
  "password": "'"${password}"'",
  "otpCode": "'"${otpCode}"'",
  "deviceName": "REST Client (cookies)",
  "tokenDelivery": "cookie"
}'

# hello
curl \
  'https://'"${apiUrl}"'/authors/{{name}}'

# PostXmlFile
curl \
  -X POST \
  'https://example.com/comments' \
  -H 'Content-Type: application/xml' \
  -H 'Authorization: token xxx' \
  --data-binary '@C:\Users\Default\Desktop\demo.xml'

# SampleWithFunctions
curl \
  -X POST \
  'https://api.example.com/comments' \
  -H 'Content-Type: application/xml' \
  -H 'Date: Sun, 25 Oct 2026 07:26:26 GMT' \
  --data-raw '{
    "user_name": "",
    "request_id": "5c6d6ee8-e677-451c-9869-d0809daff7ae",
    "updated_at": "1792913187",
    "created_at": "1792826787",
    "review_count": "93",
    "custom_date": "2026-10-25",
    "local_custom_date": "2026-10-25"
}'
