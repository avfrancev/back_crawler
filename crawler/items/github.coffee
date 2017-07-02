Gurkha = require 'gurkha'

module.exports =
	{
		page: ->
			return new Gurkha(
				{ 
					posts:
						'$rule': '.blog-post'
						title:
							'$rule': '.blog-post-title a'
							'$sanitizer': ($elem) ->
								$elem.text()
						link:
							'$rule': '.blog-post-title a'
							'$sanitizer': ($elem) ->
								'https://github.com'+$elem.attr('href')
						posted_at:
							'$rule': '.blog-post .blog-post-meta li.meta-item:first-child'
							'$sanitizer': ($elem) ->
								$elem.text()
								
					next_link:
						'$rule': 'a.next_page'
						'$sanitizer': ($elem) ->
							'https://github.com'+$elem.attr('href')
					}
					{
						options:
							normalizeWhitespace: true
					}
			)
		post: ->
			return new Gurkha(
				image:
					'$rule': '.blog-post-body img'
					'$sanitizer': ($elem) ->
						return $elem.attr('src')
			)
	}
