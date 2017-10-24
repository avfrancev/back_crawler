fs                                  = require 'fs'
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
https = require('https')
http = require('http')

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

	type Stats {
		start: String
		stop: String
		parsingTime: String
		size: String
	}

	type Post {
		id: String
		title: String
		link: String
		images: [String]
		status: String
		parsed_at: String
		itemId: String
		stats: Stats
		tags: [String]
		item: Item
		owner: User
	}

	type Query {
		items: [Item]
		item(id: String): Item
		users: [User]
		post(id: String): Post
		posts(limit: Int): [Post]
	}

	type Mutation {

		updatePost(
			id: String!
			title: String
			link: String
			status: String
		): Post

		removePost(
			id: String!
			itemId: String
		): Post

		removePosts(
			id: String!
		): Post

		updateItem(
			id: String!
			active: Boolean
			name: String
			full_name: String
			depth: Int
			concurrency: Int
			schemas: String
			parseInterval: Int
			data: ItemDataInput
			owner: String
		): Item

	}

	type Subscription {
		PostAdd: Post
		PostChange: Post
		PostRemove: Post
		ItemChange: Item
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
		posts: (_, {limit}) -> r.table('Post').orderBy(r.desc('parsed_at')).limit(limit || 999).run()

	Mutation:
		updatePost: (_, a) ->
			updateModel('Post', a)
		removePosts: (_, a) ->
			r.table('Post').filter({ itemId: a.id }).delete().run().then ->
				r.table('Item').get(a.id).then (item) ->
					item.postsCount = 0
					pubsub.publish("ItemChange", {"ItemChange": {id: item.id, postsCount: item.postsCount}})
					return
				return
		removePost: (_, a) ->
			await r.table('Post').get(a.id).delete().run()
			postsCount = await r.table('Post').filter({itemId:a.itemId}).count().run()
			updateModel 'Item',
				id: a.itemId
				postsCount: postsCount
			return
		updateItem: (_, a) ->
			if a.schemas
				fs.writeFile "./crawler/items/#{a.name}.coffee", a.schemas, (err) ->
					if err then return console.log(err)
					return
			r.table('Item').get(a.id).then (_item) ->
				r.table('Item').update(a, {returnChanges:true}).run().then (data, err) ->
					if err then console.error err; return err
					if data.changes.length > 0
						if a.parseInterval and a.parseInterval != _item.parseInterval
							_item.parseInterval = a.parseInterval
							setJob _item
							# console.log "parseInterval changed", a.parseInterval

						return data.changes[0].new_val
					else
						return r.table("Item").get(a.id)


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
			# 	console.log payload
			# 	payload


updateModel = (model, payload) ->
	# console.log payload
	r.table(model).update(payload, {returnChanges:true}).run().then (data, err) ->
		if err then console.error err; return err
		if data.changes.length > 0
			# pubsub.publish("#{model}Change", {"#{model}Change": data.changes[0].new_val})
			if model is 'Item' and payload.parseInterval
				console.log "parseInterval changed", payload.parseInterval
			# console.log "asdasdasdasd"
			return data.changes[0].new_val
		else
			return r.table("#{model}").get(payload.id)


r.table('Item').changes({includeTypes: true}).run().then (c) -> publishChanges('Item', c)
r.table('Post').changes({includeTypes: true}).run().then (c) -> publishChanges('Post', c)

publishChanges = (model, cursor) ->
	cursor.each (err, x) ->
		switch x.type
			when 'change'
				pubsub.publish("#{model}Change", {"#{model}Change": x.new_val})
			when 'add'
				pubsub.publish("#{model}Add", {"#{model}Add": x.new_val})
			when 'remove'
				pubsub.publish("#{model}Remove", {"#{model}Remove": x.old_val})
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

app.get '/api/remove_item_posts', auth.authenticate(),  (req, res) ->
	# console.log req.query.id
	if req.query.id
		r.table('Post').filter({itemId: req.query.id}).delete().then (x) ->

	res.json parse: req.query.id
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
