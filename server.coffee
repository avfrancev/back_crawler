fs                                  = require 'fs'
fse                                 = require 'fs-extra'
archiver                            = require('archiver')
express                             = require 'express'
cors                                = require 'cors'
bodyParser                          = require 'body-parser'
bcrypt                              = require('bcrypt')
jwt                                 = require("jwt-simple")
{ createServer }                    = require 'http'
{ execute, subscribe }              = require 'graphql'
{ graphqlExpress, graphiqlExpress } = require 'graphql-server-express'
{ makeExecutableSchema }            = require 'graphql-tools'
{ SubscriptionServer }              = require 'subscriptions-transport-ws'
{ PubSub }                          = require 'graphql-subscriptions';
https                               = require('https')
http                                = require('http')

pubsub = new PubSub()
r      = require('rethinkdbdash')({db: 'horizon', timeout: 200})


cfg = require './config.coffee'


# crawler = require('./crawler/index.coffee')(cfg)

{ addItemToQueue, setJob } = require './NEWTEST'



# setTimeout ->
# 	crawler.addItemToQueue('a8f18010-45a6-4e3d-bee6-df8da404806b')
# , 3000

app = express()

app.use cors()

app.use bodyParser.urlencoded(extended: true)
app.use bodyParser.json()


typeDefs = """

	type User {
		id: String
		username: String
		displayName: String
		avatar_url: String
		posts: [Post]
		items: [Item]
	}

	type Item {
		id: String
		name: String
		full_name: String
		active: Boolean
		captureSelector: String
		takeScreenshot: Boolean
		link: String
		logo: String
		loading: Boolean
		depth: Int
		concurrency: Int
		parseInterval: Int
		status: String
		schemas: String
		postsCount: Int
		nextParseDate: String
		data: ItemData
		posts(limit: Int): [Post]
		owner: User
	}

	type ItemData {
		loading: Boolean
		depth: Int
		parsedPagePostsCount: Int
		progress: Int
		PagePostsCount: Int
	}

	input ItemDataInput {
		loading: Boolean
		depth: Int
		parsedPagePostsCount: Int
		progress: Int
		PagePostsCount: Int
	}

	input UserInput {
		id: String!
	}

	input ItemInput {
		id: String
		name: String
	}

	type Stats {
		start: String
		stop: String
		parsingTime: String
		size: String
	}

	input PostsFilter {
		status: String
		itemId: String
		itemIds: [String]
		published: String
		searchQuery: String
	}

	type Post {
		id: String
		title: String
		link: String
		images: [String]
		status: String
		parsed_at: String
		published: Boolean
		hasScreenshot: String
		itemId: String
		stats: Stats
		tags: [String]
		item: Item
		owner: User
	}

	type Query {
		items: [Item]
		item(id: String): Item
		post(id: String): Post
		posts(limit: Int, filter: PostsFilter): [Post]
		users: [User]
	}

	type Mutation {

		updatePost(
			id: String!
			title: String
			link: String
			status: String
			published: Boolean
		): Post

		removePost(
			id: String!
			item: ItemInput
		): Post

		removePosts(
			item: ItemInput!
		): Post

		removeItem(
			id: String!
		): Item

		updateItem(
			id: String!
			active: Boolean
			name: String
			full_name: String
			link: String
			logo: String
			depth: Int
			captureSelector: String
			takeScreenshot: Boolean
			concurrency: Int
			schemas: String
			parseInterval: Int
			data: ItemDataInput
			owner: String
		): Item

		addItem(
			active: Boolean
			name: String
			full_name: String
			link: String
			logo: String
			depth: Int
			captureSelector: String
			takeScreenshot: Boolean
			concurrency: Int
			schemas: String
			parseInterval: Int
			data: ItemDataInput
			owner: String
		): Item

	}

	type ItemSubscribtion {
		mutation: String
		node: Item
	}
	type PostSubscribtion {
		mutation: String
		node: Post
	}

	type Subscription {
		PostAdd: Post
		PostRemove: Post
		PostChange: PostSubscribtion
		ItemChange: ItemSubscribtion
	}

	schema {
		query: Query
		mutation: Mutation
		subscription: Subscription
	}

"""



resolvers =
	# Post: -> { id: 1, name: '12312312' }
	User:
		items: (user, args) -> r.table('Item').filter({owner: user.id}).run()
		posts: (user, args) -> r.table('Post').filter({owner: user.id}).run()
	Item:
		owner: (item) -> r.table('users').get(item.owner).run()
		postsCount: (item) -> r.table('Post').filter({itemId: item.id}).count().run()
		posts: (item, args) ->
			r.table('Post').filter({itemId: item.id}).limit(args.limit || 999).run()
	Post:
		owner: (item) -> r.table('users').get(item.owner).run()
		item: (post, args) ->
			# r.table('Item').get(post.itemId).run().then (console.log )
			r.table('Item').get(post.itemId).run()
	Query:
		items: -> r.table('Item').run()
		users: -> r.table('users').run()
		item: (_, {id}) -> r.table('Item').get(id).run()
			# new Promise (resolve) ->
			# 	r.table('Item').get(id).run().then (data) ->
			# 		setTimeout ->
			# 			resolve data
			# 		, 1000
			# 		return
			# 	return

		post: (_, {id}) -> r.table('Post').get(id).run()
		posts: (_, a) ->
			f = {}
			f = {published: a.filter.published == 'true'} if a.filter.published
			r.table('Post')
				.filter( (doc) ->
					if a.filter.itemIds?.length > 0
						return r.expr(a.filter.itemIds).contains(doc('itemId'))
					doc
				)
				.filter(f)
				.filter((x) ->
					x('title').match("(?i)#{a.filter.searchQuery || ''}")
				)
				.orderBy(r.desc('parsed_at')).limit(a.limit || 999).run()

	Mutation:
		updatePost: (_, a) ->
			updateModel('Post', a)


		removePosts: (_, a) ->
			await r.table('Post').filter({ itemId: a.item.id }).delete().run()
			fse.removeSync "/home/screenshots/#{a.item.name}"
			updateModel 'Item',
				id: a.item.id
				postsCount: '-1'
				data:
					progress: 0
			return

		removePost: (_, a) ->
			# console.log a
			fs.unlink "/home/screenshots/#{a.item.name}/#{a.id}.jpeg", (err) ->
				console.log err if err
				# console.log "/home/screenshots/#{a.item.name}/#{a.id}.jpeg"
				return

			await r.table('Post').get(a.id).delete().run()
			postsCount = await r.table('Post').filter({itemId:a.item.id}).count().run()
			updateModel 'Item',
				id: a.item.id
				postsCount: postsCount + 10
			return
		removeItem: (_, a) ->
			# console.log a
			r.table("Item").get(a.id).delete().run()
			return

		addItem: (_, a) ->
			# console.log a
			for key in ['name', 'full_name', 'link']
				unless a[key] && a[key].length > 0
					return Error "Fill form properly"
			item = await r.table('Item').filter({name: a.name}).count().run()
			if item > 0
				return new Error "Name #{a.name} allready exist!"

			a = {
				a...
				loading: false
				status: 'success'
				nextParseDate: new Date
				data:
					progress: 0
					depth: 0
			}

			fs.writeFile "./crawler/items/#{a.name}.coffee", a.schemas, (err) ->
				if err then return console.log(err)
				return

			item = await r.table('Item').insert(a, {returnChanges:true}).run()
			# console.log '================'
			# console.log item
			item = item.changes.new_val
			return item || a

		updateItem: (_, a) ->
			if a.schemas
				fs.writeFile "./crawler/items/#{a.name}.coffee", a.schemas, (err) ->
					if err then console.log(err)
					return
			# old_item = await r.table('Item').get(a.id).run()
			# console.log ' 2 -------'
			item = await r.table('Item').get(a.id).update(a, {returnChanges:true}).run()
			if item.changes.length > 0
				{ old_val, new_val } = item.changes[0]
				if a.parseInterval and a.parseInterval != old_val.parseInterval
					setJob new_val
				return new_val
			return a
					# _item.parseInterval = a.parseInterval

					# if data.changes.length > 0
					#
					# 	return data.changes[0].new_val
					# else
					# 	return r.table("Item").get(a.id)
			# r.table('Item').get(a.id).then (_item) ->
			# 	r.table('Item').update(a, {returnChanges:true}).run().then (data, err) ->
			# 		if err then console.error err; return err
			# 		if data.changes.length > 0
			# 			if a.parseInterval and a.parseInterval != _item.parseInterval
			# 				_item.parseInterval = a.parseInterval
			# 				setJob _item
			# 				# console.log "parseInterval changed", a.parseInterval
			#
			# 			return data.changes[0].new_val
			# 		else
			# 			return r.table("Item").get(a.id)


	Subscription:
		PostRemove:
			subscribe: -> pubsub.asyncIterator('PostRemove')
		PostAdd:
			subscribe: -> pubsub.asyncIterator('PostAdd')
		PostChange:
			subscribe: -> pubsub.asyncIterator('PostChange')
		ItemChange:
			subscribe: -> pubsub.asyncIterator('ItemChange')
			# resolve: (payload, args, context, info) ->
			# 	console.log payload['ItemChange']
			# 	{
			# 		mutation: 'LJKASF'
			# 		payload: payload['ItemChange']
			# 	}


updateModel = (model, payload) ->
	{id, obj...} = payload
	console.log "UPDATING :: #{model}"
	# console.log payload
	r.table(model).get(id).update(obj).run()
	# console.log M
	# return M
	# console.log M
	# # console.log payload
	# r.table(model).update(payload, {returnChanges:true}).run().then (data, err) ->
	# 	console.log data
	# 	if err then console.error err; return err
	# 	if data.changes.length > 0
	# 		# pubsub.publish("#{model}Change", {"#{model}Change": data.changes[0].new_val})
	# 		if model is 'Item' and payload.parseInterval
	# 			console.log "parseInterval changed", payload.parseInterval
	# 		# console.log "asdasdasdasd"
	# 		return data.changes[0].new_val
	# 	else
	# 		return r.table("#{model}").get(payload.id)
	# # 	return
	# # return


r.table('Item').changes({includeTypes: true}).run().then (c) -> publishChanges('Item', c)
r.table('Post').changes({includeTypes: true}).run().then (c) -> publishChanges('Post', c)

publishChanges = (model, cursor) ->
	cursor.each (err, x) ->
		switch x.type
			when 'change'
				# console.log 'CHANGES: ', model
				pubsub.publish("#{model}Change", {"#{model}Change": {mutation: 'UPDATED', node: x.new_val}})
			when 'add'
				pubsub.publish("#{model}Change", {"#{model}Change": {mutation: 'CREATED', node: x.new_val}})
			when 'remove'
				pubsub.publish("#{model}Change", {"#{model}Change": {mutation: 'DELETED', node: x.old_val}})
				# if model is 'Post'
				# 	console.log "DELETE POST: ", x
				# 	pubsub.publish("PostRemove", {"PostRemove": x.old_val.id})






schema = makeExecutableSchema(
	typeDefs: typeDefs
	resolvers: resolvers)




app.use '/graphql', graphqlExpress(schema: schema)

app.use '/graphiql', graphiqlExpress(
	endpointURL: '/graphql'
	# subscriptionsEndpoint: SUBSCRIPTIONS_PATH
	)

auth = require("./auth.coffee")(r)
app.use auth.initialize()

app.get '/', (req, res) ->
	res.json status: 'My API is alive!'
	return

app.get '/parse', auth.authenticate(),  (req, res) ->
	# crawler.emitter.emit 'parse', req.query.id
	addItemToQueue req.query.id
	# console.log req.query.id
	res.json parse: req.query.id
	return

app.get '/get-screenshots', (req, res) ->
	# check folder existing
	if !fse.existsSync("/home/screenshots/#{req.query.item}")
		res.status(500).send error: "Folder not exist"
		return
	archive = archiver('zip')
	archive.on 'error', (err) ->
		res.status(500).send error: err.message
		return
	# #on stream closed we can end the request
	res.on 'close', ->
		console.log 'Archive wrote %d bytes', archive.pointer()
		res.status(200).send('OK').end()
	# #set the archive name
	res.attachment "#{req.query.item}.zip"
	# #this is the streaming magic
	archive.pipe res
	# archive.append fs.createReadStream('server.coffee'), name: 'file.txt'
	archive.directory "/home/screenshots/#{req.query.item}", false
	# #you can add a directory using directory function
	# #archive.directory(dirPath, false);
	archive.finalize()
	return



app.get '/auth/user', auth.authenticate(), (req, res) ->
	delete req.user.hash
	res.status(200).json
		status: 'success'
		data: req.user
	return

console.log bcrypt.hashSync('admin', 11)
app.post '/auth/login', (req, res) ->
	if req.body.username and req.body.password
		r.table('users').filter(
			provider: 'local'
			username: req.body.username
		).pluck('id', 'hash').then (user) ->
			# hash = bcrypt.hashSync('admin', 11)
			if user[0] and bcrypt.compareSync req.body.password, user[0].hash
				console.log user[0]
				payload = id: user[0].id
				token = jwt.encode(payload, cfg.jwtSecret)
				user[0].token = token
				res.json
					status: 'success'
					data:
						id: user[0].id
						token: token
			else
				res.sendStatus 401
	else
		res.sendStatus 401
	return

console.log process.env.NODE_ENV
if process.env.NODE_ENV is 'prod'

	options =
		key: fs.readFileSync(cfg[process.env.NODE_ENV].key).toString()
		cert: fs.readFileSync(cfg[process.env.NODE_ENV].cert).toString()
		ciphers: 'ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-RSA-AES128-SHA256:ECDHE-RSA-AES256-SHA:ECDHE-RSA-AES256-SHA384'
		honorCipherOrder: true
		secureProtocol: 'TLSv1_2_method'

	httpServer = https.createServer(options, app).listen(cfg.PORT + 1)

else
	httpServer = http.createServer(app).listen(cfg.PORT)


new SubscriptionServer(
	{
		execute,
		subscribe,
		schema,
	},
	{
		path: cfg.SUBSCRIPTIONS_PATH
		server: httpServer
	}
)

# server.listen cfg.PORT, ->
# 	console.log "API Server is now running on http://localhost:#{cfg.PORT}/graphql"
# 	console.log "API Subscriptions server is now running on ws://localhost:#{cfg.PORT}#{cfg.SUBSCRIPTIONS_PATH}"
