
Rx = require 'rxjs'
needle = require 'needle'
webshot = require('webshot')
schedule = require('node-schedule')
# cronParser = require('cron-parser')
# toml = require('toml')
path = require('path')
fs = require('fs')
# exec = require('child_process').exec





# ============== Local Modules ==============
r = undefined
DB = undefined
jobs = undefined
config = undefined
# ============== Local Modules ==============



# ============== TEST ==============
checkIfPostExist = (post) ->
	new Promise (resolve, reject) ->
		r.table('Post').filter(r.row('link').eq(post.link)).then (result) ->
			unless result[0]
				resolve { isNewPost: true, post }
				return
			else
				resolve { isNewPost: false, post: result[0] }
			return
		return


__parsePost = (post, item, schemas) ->
	Rx.Observable
		.fromPromise(checkIfPostExist(post))
		# .delay(500)
		.flatMap((x) ->
			if x.isNewPost
				# console.log "[+] #{x.post.title}"
				Rx.Observable
					.fromPromise(getBody(x.post.link, x.post))
					.retryWhen( (errors) ->
						console.log error
						return errors.delay(2200)
					)
					.map((x) ->
						# console.log __savePost { itemId:  }
						# console.log __savePost
						post = Object.assign {}, x, schemas.post().parse(x.body)[0]
						delete post.body
						if typeof post.images is 'string'
							post.images = [post.images]
						post.tags = post.tags || []
						if typeof post.tags is 'string'
							post.tags = [post.tags]
						post.itemId = item.id
						post.owner = item.owner
						post.status = 'pending'
						# post.timestamp = new Date().getTime().valueOf()
						post.parsed_at = new Date().getTime()
						# post.
						# post.item =
						# 	name: item.name
						# 	full_name: item.full_name
						# 	logo: item.logo
						post
						# Rx.Observable.fromPromise __savePost post
					)
					.concatMap((post) -> __savePost post)
					.map((x) ->
						post = x.changes[0].new_val
						console.log "[+] #{post.title}", post
						post
					)
					# .concatAll()
					# .do(console.log)
					# .concatMap((post) ->
					# 	console.log post
					# 	__savePost post
					# )
					# .do(console.log)
					# .do(console.log )
			else
				# console.table x.post
				# console.log "[-] #{x.post.title}"
				return Rx.Observable.of(x.post).delay(2)
		)
		# .merge(3)
		# .delay(500)
		# .do(console.log )

__savePost = (post) ->
	r.table('Post').insert(post, {returnChanges: true}).run()


__parsePage = (item, link, schemas) ->
	Rx.Observable.fromPromise(getBody(link))
		# .retryWhen( (errors) ->
		# 	console.log errors
		# 	return errors.delay(2200)
		# )
		.map((x) ->
			console.log schemas.page().parse(x.body)
			schemas.page().parse(x.body)[0]
		)
		.do((x) -> console.log "-------- PAGE #{item.data.depth} --------" )
		.concatMap(
			( (x) ->
				parsedPagePostsCount = 0
				DB.updateModel 'Item',
					id: item.id
					data:
						depth: item.data.depth
						PagePostsCount: x.posts.length
						parsedPagePostsCount: parsedPagePostsCount

				Rx.Observable.from(x.posts)
					.mergeMap(((post) -> __parsePost post, item, schemas), +item.concurrency)
					# .do(console.log)
					.flatMap((x) ->
						unless x.id
							# log = item.logs[item.logs.length-1]
							# log.newPosts.push x
							# console.log log
							# updateItemLog(item.id, log)
							console.log "SAVING/////"
							# __savePost(item, x)
							Rx.Observable.of(x)
						else Rx.Observable.of(x)
					)
					.do( (xx) ->
						++parsedPagePostsCount
						progress = Math.floor (100 / (item.depth)) * (item.data.depth - 1) + ((parsedPagePostsCount * (100 / item.depth)) / item.data.PagePostsCount)
						DB.updateModel 'Item',
							id: item.id
							data:
								progress: progress
								parsedPagePostsCount: parsedPagePostsCount
					)
					# .concatAll()
					.toArray()

			), (_item, posts) ->
				{next_link: _item.next_link, posts}
		)
		.flatMap((x) ->
			item.data.depth++
			# x = schemas.page().parse(x.body)[0]
			# console.log x.next_link
			if item.data.depth <= item.depth
				__parsePage(item, x.next_link, schemas)
			else Rx.Observable.empty()
		)


__parseItem = (id) ->
	if !id then console.error 'Specify the ID !'; return
	new Promise (resolve) ->
		console.log 'OARSING>>>>>>'
		r.table('Log').insert({start: new Date().getTime()}, {returnChanges: true}).then (log) ->
			r.table('Item').get(id).then (item) ->
				console.warn "START #{item.full_name}"

				item.data.depth = 1
				schemas = require "./items/#{item.name}.coffee"

				item.log =
					startParse: new Date().getTime()
					itemId: item.id
					concurrency: item.concurrency
					depth: item.depth
					posts: []


				DB.updateModel 'Item',
					id: item.id
					loading: true
					status: 'parsing'
					data:
						depth: item.data.depth
						parsedPagePostsCount: 0


				__parsePage(item, item.link, schemas)
					.subscribe(

						complete: ->

							item.log.stopParse = new Date().getTime()
							item.log.parsingTime = item.log.stopParse - item.log.startParse
							# updateItemLog(item.id, logs)
							console.log item.log
							setJob item
							# nextParseDate = jobs.addMinutes new Date().getTime(), +item.parseInterval * 60 || config.parseInterval

							DB.updateModel 'Item',
								id: item.id
								loading: false
								status: ''
								lastParseDate: new Date().getTime()

							console.warn "COMPLETE #{item.full_name}"
							resolve(item)
							# emitter.emit 'parse', item.id
							return
					)
				return
			return
		return


getBody = (url, post) ->

	result =
		body: ''
		stats:
			start: new Date().getTime()

	if post
		result = Object.assign result, post

	new Promise (resolve, reject) =>
		options =
			open_timeout: 5000
			read_timeout: 5000
			compressed:   true

		stream = needle.get url, options

		stream.on 'readable', ->
			while chunk = @read()
				result.body += chunk
			return

		# stream.on 'timeout', (err) ->
		# 	console.log "timeout"
		# 	console.error err
		# 	return

		stream.on 'err', (err) ->
			console.log 'ERROR'
			console.error err
			reject err
			# setTimeout ->
			# 	console.log '.................'
			# 	getBody url, post
			# , 5000
			return

		stream.on 'end', (err) =>
			result.stats.stop = new Date().getTime()
			result.stats.parsingTime = result.stats.stop - result.stats.start
			result.stats.size = result.body.length
			resolve result
			return

		return

# ============== TEST ==============

items = []

setJob = (item, startParseDate) ->
	if item.active
		clearInterval items[item.id] if items[item.id]
		nextParseDate = startParseDate || new Date().getTime() + item.parseInterval * 60 * 60 * 1000
		interval = (new Date nextParseDate) - new Date().getTime()
		console.log "Set job #{item.name}: ", new Date nextParseDate
		items[item.id] = setInterval ->
			# console.log item.parseInterval
			emitter.emit 'parse', item.id
			# setJob item
		, interval
	else
		nextParseDate = null
	DB.updateModel 'Item',
		id:             item.id
		nextParseDate:  nextParseDate




EventEmitter = require('events').EventEmitter
emitter = new EventEmitter()

Rx.Observable.fromEvent(emitter, 'parse')
	.filter((x) -> x.length > 0)
	.map( (x) ->
		DB.updateModel 'Item',
			id: x
			status: 'queued'
			data: progress: 0
		console.log x
		x
	)
	.concatMap((x) ->
		__parseItem(x)
	)
	.subscribe()



module.exports = (config) ->

	module = {}

	r = require('rethinkdbdash')({db: config.DBName})
	DB = require('./DB.coffee')(config)
	# jobs = require('./jobs.coffee')(config)

	# r.table('Item').then (_items) ->
	# 	_items.map (item) ->
	# 		nextParseDate = item.nextParseDate if item.nextParseDate > new Date().getTime()
	# 		setJob item, nextParseDate
	# 		return

	module.emitter = emitter
	module.setJob = setJob

	module
