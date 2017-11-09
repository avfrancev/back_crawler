fs      = require 'fs'
fse     = require 'fs-extra'
needle  = require('needle')
moment  = require 'moment'
webshot = require('webshot')
cheerio = require 'cheerio'
config  = require '../config'
log     = require('cllc')(module)

async = require 'async'

r = require('rethinkdbdash')({db: 'horizon'})

needle.defaults
	open_timeout: 4400
	compressed:   true
	parse_response: true



updateModel = (model, payload) ->
	r.table(model).update(payload, {returnChanges:true}).run().then (data, err) ->
		if err then console.error err; return err
		if data.changes.length > 0
			pubsub.publish("#{model}Change", {"#{model}Change": data.changes[0].new_val})
			data.changes[0].new_val
		else
			return r.table("#{model}").get(payload.id)

errorCount = 0

getBody = (url, post, l) ->
	result =
		body: ''
		stats:
			start: new Date().getTime()

	if post
		result = Object.assign result, post

	needle('get', url)
	.then (res) ->
		errorCount = 0
		result.body = res.body
		result.stats.stop = new Date().getTime()
		result.stats.parsingTime = result.stats.stop - result.stats.start
		result.stats.size = result.body.length
		return result
	.catch (err) ->
		if ++errorCount > 5
			return Promise.reject(err)
		l.error err
		await sleep 1200
		return getBody url, post, l

sleep = (ms) ->
	new Promise (resolve) ->
		setTimeout resolve, ms

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

contentAnalize = (content) ->
	unless content and content.length > 0
		return []

	corpus = {}
	words = []
	content.split(' ').forEach (word) ->
		unless 4 < word.length < 20
			return
		if corpus[word]
			corpus[word]++
		else
			corpus[word] = 1
		return

	for prop of corpus
		if corpus[prop] > 2
			words.push
				word: prop
				count: corpus[prop]

	words.sort (a, b) ->
		b.count - (a.count)

	return words.slice(0,5)

makeScreenshot = ({item, post}, done) ->
	!fse.existsSync("/home/screenshots/#{item.name}") && fse.mkdirSync("/home/screenshots/#{item.name}")

	options =
		streamType: 'jpeg'
		captureSelector: item.captureSelector
		quality: 30

	webshot post.link, "/home/screenshots/#{item.name}/#{post.id}.jpeg", options, (err) ->
		console.log err if err
		updateModel 'Post',
			id: post.id
			hasScreenshot: true
		done()
		return
	return

makeScreenshotQueue = async.queue(makeScreenshot, 1)

parsePosts = (item, posts, schema, l) ->
	parsedPagePostsCount = 0
	item.data.PagePostsCount = posts.length
	console.log posts
	new Promise (resolve, reject) ->
		for post in posts.reverse()
			p = await checkIfPostExist post
			++parsedPagePostsCount
			progress = Math.floor (100 / (item.depth)) * (item.data.depth) + ((parsedPagePostsCount * (100 / (item.depth))) / item.data.PagePostsCount)

			if p.isNewPost
				try
					b = await getBody post.link, post, l
				catch err
					reject(err)
					return

				l "[ + ] #{post.title}"
				parsed_body = schema.post().parse(b.body)[0]
				keywords = contentAnalize parsed_body.content
				delete b.body
				delete b.content
				post = {
					post...
					parsed_body...
					b...
					keywords
				}
				if typeof post.images is 'string'
					post.images = [post.images]
				post.tags = post.tags || []
				if typeof post.tags is 'string'
					post.tags = [post.tags]
				post.itemId = item.id
				post.owner = item.owner
				post.parsed_at = new Date().getTime()
				post.published = false

				newPost = await r.table('Post').insert(post, {returnChanges: true}).run()

				post = newPost.changes[0].new_val

				makeScreenshotQueue.push({item, post}) if item.takeScreenshot


			updateModel 'Item',
				id: item.id
				data:
					progress: progress
					parsedPagePostsCount: parsedPagePostsCount

		resolve()
		return

parsePage = ({ item, l }, done) ->
	_done = done
	delete require.cache[require.resolve("./items/#{item.name}.coffee")]
	schema = require "./items/#{item.name}.coffee"

	try
		{body} = await getBody(item.link, null, l)
	catch err
		done(err, {item, l})
		return

	parsed_body = schema.page().parse(body)[0]

	try
		await parsePosts item, parsed_body.posts, schema, l
	catch err
		done(err, {item,l})
		return

	if ++item.data.depth < item.depth && typeof parsed_body.next_link is 'string'
		item.link = parsed_body.next_link
		parsePage {item, l}, _done
	else
		done(null, {item, l})
	return

parseItem = ( item, done) ->
	l = require('cllc')(item.name)
	l "START"

	updateModel 'Item',
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

		updateModel 'Item',
			id: item.id
			status: 'queued'
			data: progress: 0

		q.push item, (err, data) ->
			{item,l} = data
			if err
				status = 'error'
				console.error 'ERROR :: ', err
			else
				status = 'success'

			updateModel 'Item',
				id: item.id
				loading: false
				status: status
				lastParseDate: new Date().getTime()

			setJob item

		return
	return

items = []

setJob = (item, startParseDate) ->
	l = require('cllc')(item.name)
	if item.active
		clearInterval items[item.id] if items[item.id]
		nextParseDate = startParseDate || new Date().getTime() + item.parseInterval * 60 * 60 * 1000
		interval = (new Date nextParseDate) - new Date().getTime()
		l "Next job at: #{moment(nextParseDate).format("HH:mm:ss")}"
		items[item.id] = setInterval ->
			addItemToQueue item.id
		, interval
	else
		nextParseDate = null
	updateModel 'Item',
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
