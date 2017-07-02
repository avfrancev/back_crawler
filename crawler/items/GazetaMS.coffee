Gurkha = require 'gurkha'

module.exports =
	{
			page: ->
				return new Gurkha(
					{
						posts:
							'$rule': '#content article'
							title:
								'$rule': '.entry-title a'
								'$sanitizer': ($elem) ->
									$elem.text()
							link:
								'$rule': '.entry-title a'
								'$sanitizer': ($elem) ->
									$elem.attr('href')
							# text:
							# 	'$rule': '.entry-summary p'
							# 	'$sanitizer': ($elem) ->
							# 		$elem.text()
							posted_at:
								'$rule': '.entry-meta time'
								'$sanitizer': ($elem) ->
									return $elem.attr('datetime')
							image: '.post-thumb img'
							'$sanitizer': ($elem) ->
								return $elem.attr('src')
						next_link:
							'$rule': 'a.next'
							'$sanitizer': ($elem) ->
								return $elem.attr('href')
						}
						{
							options:
								normalizeWhitespace: true
						}
				)
			post: ->
				return new Gurkha(
					tags:
						'$rule': '.tag-list a'
				)
	}
