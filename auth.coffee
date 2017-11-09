passport = require('passport')
passportJWT = require('passport-jwt')
cfg = require('./config.coffee')
ExtractJwt = passportJWT.ExtractJwt
Strategy = passportJWT.Strategy

params =
	secretOrKey: cfg.jwtSecret
	jwtFromRequest: ExtractJwt.fromAuthHeader()



module.exports = (r) ->
	strategy = new Strategy(params, (payload, done) ->
		r.table('users').get(payload.id).then (user) ->
			if user
				done null, user
			else
				done new Error('User not found'), null
	)

	passport.use strategy

	{
		initialize: ->
			passport.initialize()
		authenticate: ->
			passport.authenticate 'jwt', cfg.jwtSession

	}
