
{ PubSub } = require 'graphql-subscriptions';

pubsub = new PubSub()

module.exports = (config) ->

	r = require('rethinkdbdash')({db: config.DBName})

	module = {}

	module.updateModel = (model, payload) ->
		# console.log "UPDATING #{model}", payload
		r.table(model).update(payload, {returnChanges:true}).run().then (data, err) ->
			# console.log data
			if err then console.error err; return err
			if data.changes.length > 0
				pubsub.publish("#{model}Change", {"#{model}Change": data.changes[0].new_val})
				data.changes[0].new_val
			else
				return r.table("#{model}").get(payload.id)

	module.watchDBChanges = (jobs) ->
		r.db('horizon').table('Item').changes({includeTypes:true}).run conn, (err, cursor) ->
			throw err if err
			cursor.each (err, x) ->
				if x.type in ['add', 'change']
					if new Date(x.new_val.nextParseDate).getTime() != new Date(x.old_val.nextParseDate).getTime()
						jobs.scheduleItem x.new_val.id, x.new_val.name, x.new_val.nextParseDate
				else
					jobs.removeSchedule x.old_val.id, x.old_val.name
				# if x.type in ['add']
				# 	jobs.scheduleItem x.new_val.id, x.new_val.name, x.new_val.nextParseDate
				# 	return
				# if x.type in ['change']
				# 	if new Date(x.new_val.nextParseDate) > new Date(x.old_val.nextParseDate)
				# 	# if new Date(x.new_val.nextParseDate) > new Date()
				# 		jobs.scheduleItem x.new_val.id, x.new_val.name, x.new_val.nextParseDate
				# 	else
				# 		nextParseDate = jobs.addMinutes new Date(), x.new_val.parseInterval || config.parseInterval
				# 		console.log nextParseDate
				# 		module.updateItem
				# 			id: x.old_val.id
				# 			nextParseDate: nextParseDate
				return
			return

	module.updateItem = (item) ->
		r.db('horizon').table('Item').update(item).run(conn)
		return

	module
