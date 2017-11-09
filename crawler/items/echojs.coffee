Gurkha = require 'gurkha'

module.exports =
	{
		page: ->
			return new Gurkha(
				posts:
					'$rule': '#newslist article'
					title: 'h2 a'
					link:
						'$rule': 'h2 a'
						'$sanitizer': ($elem) ->
							return $elem.attr('href')
				next_link:
					'$rule': '#newslist a.more'
					'$sanitizer': ($elem) ->
						return 'http://www.echojs.com' + $elem.attr('href')
			)
		post: ->
			return new Gurkha(
				images:
					'$rule': '.content img'
					'$sanitizer': ($elem) ->
						return $elem.attr('src')
			)
	}