Gurkha = require 'gurkha'

module.exports =
	{
		page: ->
			return new Gurkha(
				posts:
					'$rule': '.post'
					title: '.post__title_link'
					link:
						'$rule': '.post__title_link'
						'$sanitizer': ($elem) ->
							return $elem.attr('href')
					posted_at:
						'$rule': '.post__time_published'
						'$sanitizer': ($elem) ->
							$elem.text()
				next_link:
					'$rule': 'a#next_page'
					'$sanitizer': ($elem) ->
						'https://habrahabr.ru' + $elem.attr('href')
			)
		post: ->
			return new Gurkha(
				images:
					'$rule': 'article.post_full img'
					'$sanitizer': ($elem) ->
						return $elem.attr('src')
			)
	}