Gurkha = require 'gurkha'

module.exports =
	{
			page: ->
				return new Gurkha(
					{
						posts:
							'$rule': '.news-item'
							title:
								'$rule': '.col-md-7 h2 a'
								'$sanitizer': ($elem) ->
									$elem.text()
							link:
								'$rule': '.col-md-7 h2 a'
								'$sanitizer': ($elem) ->
									$elem.attr('href')
							# text:
							# 	'$rule': '.entry-summary p'
							# 	'$sanitizer': ($elem) ->
							# 		$elem.text()
							posted_at:
								'$rule': '.date'
								'$sanitizer': ($elem) ->
									$elem.text()
							images: '.col-md-5 a img'
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
						'$rule': 'a[rel="tag"]'
				)
	}
