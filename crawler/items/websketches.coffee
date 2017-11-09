Gurkha = require 'gurkha'

module.exports =
	{
		page: ->
			return new Gurkha(
				posts:
					'$rule': 'aside.news-left-column .annonce-item'
					title: '.annonce-item__title a'
					link:
						'$rule': '.annonce-item__title a'
						'$sanitizer': ($elem) ->
							return 'http://websketches.ru' + $elem.attr('href')
				next_link:
					'$rule': '.pagination_span + a'
					'$sanitizer': ($elem) ->
						return 'http://websketches.ru' + $elem.attr('href')
			)
		post: ->
			return new Gurkha(
				images:
					'$rule': '.left-column img'
					'$sanitizer': ($elem) ->
						return 'http://websketches.ru' + $elem.attr('src')
			)
	}