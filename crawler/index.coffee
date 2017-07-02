
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
				return Rx.Observable
					.fromPromise(getBody(x.post.link, x.post))
					.map((x) ->
						# console.log __savePost { itemId:  }
						# console.log __savePost
						post = Object.assign {}, x, schemas.post().parse(x.body)[0]
						delete post.body
						post.itemId = item.id
						post.owner = item.owner
						post.parsed_at = new Date()
						# post.item =
						# 	name: item.name
						# 	full_name: item.full_name
						# 	logo: item.logo
						post
					)
					# .flatMap((post) -> __savePost post)
					# .map((x)->x)
					# .do(console.log )
			else
				# console.table x.post
				console.log "[-] #{x.post.title}"
				return Rx.Observable.of(x.post).delay(250)
		)
		# .merge(3)
		# .delay(500)
		# .do(console.log )

__savePost = (post) ->
	console.log "[+] #{post.title}", post
	r.table('Post').insert(post).run()


__parsePage = (item, link, schemas) ->
	Rx.Observable.fromPromise(getBody(link))
		.map((x) -> schemas.page().parse(x.body)[0])
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
					.flatMap((x) ->
						unless x.id
							# log = item.logs[item.logs.length-1]
							# log.newPosts.push x
							# console.log log
							# updateItemLog(item.id, log)
							__savePost(x)
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
	r.table('Item').get(id).then (item) ->
		console.warn "START #{item.full_name}"

		item.data.depth = 1
		schemas = require "./items/#{item.name}.coffee"

		# logs = item.logs || []

		# logs.push
		# 	startParse: new Date()
		# 	concurrency: item.concurrency
		# 	newPosts: []

		DB.updateModel 'Item',
			id: item.id
			loading: true
			# logs: logs
			data:
				depth: item.data.depth
				parsedPagePostsCount: 0


		__parsePage(item, item.link, schemas)
		.subscribe(

			complete: ->

				logs =
					stopParse: new Date()
				# updateItemLog(item.id, logs)

				# nextParseDate = jobs.addMinutes new Date(), +item.parseInterval * 60 || config.parseInterval

				DB.updateModel 'Item',
					id: item.id
					loading: false
					lastParseDate: new Date()
					# nextParseDate: nextParseDate

				console.warn "COMPLETE #{item.full_name}"
				return
		)
		return
	return


getBody = (url, post) ->

	result =
		body: ''
		stats:
			start: new Date()

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
			# console.log 'ERROR'
			# console.error err
			reject err
			return

		stream.on 'end', (err) =>
			result.stats.stop = new Date()
			result.stats.parsingTime = result.stats.stop - result.stats.start
			result.stats.size = result.body.length
			resolve result
			return

		return

# ============== TEST ==============



module.exports = (config) ->

	module = {}

	r = require('rethinkdbdash')({db: config.DBName})
	DB = require('./DB.coffee')(config)
	jobs = require('./jobs.coffee')(config)

	module.parseItem = __parseItem
		# __parseItem()
		# console.log "YYYYY )))"


	module
