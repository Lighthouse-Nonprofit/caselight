# jQuery-3 prep (POAM-017b): 'ready' event binding -> $(handler); see initializer.coffee.
$ ->
	$('#filtered_by_user select').change ->
		$('#filtered_by_user').submit()