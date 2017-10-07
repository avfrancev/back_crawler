needle = require('needle')
moment = require 'moment'
config = require './config'

DB = require('./crawler/DB')(config)


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

		reject 'Specify URL !!!'	if url.length < 1
		# if url is
		# console.log typeOf url

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

sleep = (ms) ->
	new Promise (resolve) ->
		setTimeout resolve, ms

logdown = require 'logdown'
l = logdown('#')

async = require 'async'
r = require('rethinkdbdash')({db: 'horizon'})

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

parsePosts = (item, posts, schema, l) ->
	parsedPagePostsCount = 0
	new Promise (resolve, reject) ->
		for post in posts
			p = await checkIfPostExist post



			if !p.isNewPost
				l.log "[ - ] #{post.title}"
			else
				l.log "[ + ] #{post.title}"
				b = await getBody post.link, post
				parsed_body = schema.post().parse(b.body)[0]
				delete b.body
				# console.log parsed_body
				post = { post..., parsed_body..., b... }
				if typeof post.images is 'string'
					post.images = [post.images]
				post.tags = post.tags || []
				if typeof post.tags is 'string'
					post.tags = [post.tags]
				post.itemId = item.id
				post.owner = item.owner
				post.parsed_at = new Date().getTime()

				r.table('Post').insert(post, {returnChanges: true}).run()

			++parsedPagePostsCount
			progress = Math.floor (100 / (item.depth)) * (item.data.depth - 1) + ((parsedPagePostsCount * (100 / item.depth)) / item.data.PagePostsCount)
			DB.updateModel 'Item',
				id: item.id
				data:
					progress: progress
					parsedPagePostsCount: parsedPagePostsCount

		resolve()
		return

parsePage = ({ item, l }, done) ->
	_done = done
	schema = require "./crawler/items/#{item.name}.coffee"

	# Loop pages
	if item.data.depth++ < item.depth
		try
			{body} = await getBody(item.link)
		catch err
			l.error err

		parsed_body = schema.page().parse(body)[0]
		l.log "=== PAGE ##{item.data.depth} ==="

		await parsePosts item, parsed_body.posts, schema, l

		item.link = parsed_body.next_link
		parsePage {item, l}, _done
		return

	# End parsing
	else
		await sleep 1000
		l.log '=== FINISH ==='
		DB.updateModel 'Item',
			id: item.id
			loading: false
			status: ''
			lastParseDate: new Date().getTime()
		setJob item
		done()
	return

parseItem = ({ item, l }, done) ->
	DB.updateModel 'Item',
		id: item.id
		loading: true
		status: 'parsing'
		data:
			depth: 0
			parsedPagePostsCount: 0
	parsePage { item, l }, done
	return

q = async.queue(parseItem, 1)

addItemToQueue = (id) ->
	r.table('Item').get(id).then (item) ->
		l = logdown("#::#{item.name}")
		DB.updateModel 'Item',
			id: item.id
			status: 'queued'
			data: progress: 0
		q.push {item, l}
		return
	return

items = []

setJob = (item, startParseDate) ->
	if item.active
		clearInterval items[item.id] if items[item.id]
		nextParseDate = startParseDate || new Date().getTime() + item.parseInterval * 60 * 60 * 1000
		interval = (new Date nextParseDate) - new Date().getTime()
		console.log "Set job #{item.name}: ", moment(nextParseDate).format("HH:mm:ss")
		items[item.id] = setInterval ->
			# console.log item.parseInterval
			addItemToQueue item.id
			# setJob item
		, interval
	else
		nextParseDate = null
	DB.updateModel 'Item',
		id:             item.id
		nextParseDate:  nextParseDate
	return

r.table('Item').then (_items) ->
	_items.map (item) ->
		nextParseDate = item.nextParseDate if item.nextParseDate > new Date().getTime()
		setJob item
		return


module.exports = {
	setJob: setJob
	addItemToQueue: addItemToQueue
}
