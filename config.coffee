module.exports =
	DBName:             'horizon'
	PORT:               3020
	SUBSCRIPTIONS_PATH: '/subscriptions'
	jwtSecret:         '123qwe123'
	jwtSession:
		session:         false
	dev:
		cert: '/Users/admin/SSL/avfrancev.ddns.net/cert.pem'
		key: '/Users/admin/SSL/avfrancev.ddns.net/cert.pem'
	prod:
		cert: '/etc/letsencrypt/live/avfrancev.ddns.net/cert.pem'
		key: '/etc/letsencrypt/live/avfrancev.ddns.net/privkey.pem'
		TEST: ''
