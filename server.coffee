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

pubsub = new PubSub()
r = require('rethinkdbdash')({db: 'horizon'})


cfg = require './config.coffee'


crawler = require('./crawler/index.coffee')(cfg)





# setTimeout ->
# 	crawler.parseItem('a8f18010-45a6-4e3d-bee6-df8da404806b')
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
		link: String
		logo: String
		loading: Boolean
		depth: Int
		concurrency: Int
		parseInterval: Int
		schemas: String
		data: ItemData
		postsCount: Int
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

	type Post {
		id: String
		title: String
		link: String
		itemId: String
		item: Item
		owner: User
	}

	type Query {
		items: [Item]
		item(id: String): Item
		users: [User]
		posts(limit: Int): [Post]
		post(id: String): Post
	}

	type Mutation {

		updatePost(
			id: String!
			title: String
			link: String
		): Post

		updateItem(
			id: String!
			active: Boolean
			name: String
			full_name: String
			depth: Int
			concurrency: Int
			parseInterval: Int
			data: ItemDataInput
			owner: String
		): Item
	}

	type Subscription {
		PostChange: Post
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
		posts: (_, {limit}) -> r.table('Post').limit(limit || 999).run()
	Mutation:
		updatePost: (_, a) ->
			updateModel('Post', a)
		updateItem: (_, a) ->
			updateModel('Item', a)


	Subscription:
		PostChange:
			subscribe: -> pubsub.asyncIterator('PostChange')
		ItemChange:
			subscribe: -> pubsub.asyncIterator('ItemChange')


updateModel = (model, payload) ->
	r.table(model).update(payload, {returnChanges:true}).run().then (data, err) ->
		# console.log data
		if err then console.error err; return err
		if data.changes.length > 0
			pubsub.publish("#{model}Change", {"#{model}Change": data.changes[0].new_val})
			data.changes[0].new_val
		else
			return r.table("#{model}").get(payload.id)


r.table('Item').changes({includeTypes: true}).run().then (cursor) ->
	cursor.each (err, x) ->
		switch x.type
			when 'change'
				pubsub.publish("ItemChange", {"ItemChange": x.new_val})


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


app.get '/auth/user', auth.authenticate(), (req, res) ->
	delete req.user.hash
	res.status(200).json
		status: 'success'
		data: req.user

	return

app.post '/auth/login', (req, res) ->
	if req.body.username and req.body.password
		r.table('users').filter(
			provider: 'local'
			username: req.body.username
		).pluck('id', 'hash').then (user) ->
			# hash = bcrypt.hashSync('admin', 11)
			console.log bcrypt.compareSync req.body.password, user[0].hash
			if user[0] and bcrypt.compareSync req.body.password, user[0].hash
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



server = createServer(app)

# new SubscriptionServer({ subscriptionManager: subscriptionManager },
new SubscriptionServer(
	{
		execute,
		subscribe,
		schema,
	},
	{
		path: cfg.SUBSCRIPTIONS_PATH
		server: server
	}
)

server.listen cfg.PORT, ->
	console.log "API Server is now running on http://localhost:#{cfg.PORT}/graphql"
	console.log "API Subscriptions server is now running on ws://localhost:#{cfg.PORT}#{cfg.SUBSCRIPTIONS_PATH}"
