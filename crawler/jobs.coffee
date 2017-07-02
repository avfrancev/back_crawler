schedule = require('node-schedule')


module.exports = (r, conn, config, DB, __parseItem) ->

	module = {}

	module.items = []


	module.addMinutes = (date, minutes) ->
		new Date(date.getTime() + minutes * 60000)

	module.removeSchedule = (id, name) ->
		console.log 'REMOVE schedule'
		item = module.items.filter((x) -> x.id is _id)
		item.schedule?.cancel()
		return

	module.scheduleItem = (id, name, date, parseInterval) ->
		do ( (_id, _name, _date, _parseInterval) ->

			_item = module.items.filter((x) -> x.id is _id)
			newItem = {id: _id, name: _name, date: _date}
			item = _item[0] || newItem
			module.items.push item

			if new Date(_date) > new Date()
				item.date = _date
				item.schedule?.cancel()
				console.warn " 📝  SETING JOB TO #{_name} at #{_date}"
				item.schedule = schedule.scheduleJob _date, ->
					__parseItem(_id)
					return
			else
				nextParseDate = module.addMinutes new Date(), +parseInterval? * 60 || config.parseInterval
				console.log 'updateItem ------------------->'
				DB.updateItem
					id: item.id
					nextParseDate: nextParseDate

		).bind(null, id, name, date, parseInterval)
		return

	module.setJobs = ->
		r.db('horizon').table('Item').run conn, (err, cursor) ->
			throw err if err
			cursor.each (err, x) ->
				module.scheduleItem x.id, x.name, x.nextParseDate, x.parseInterval
				return
			return
		return

	module
