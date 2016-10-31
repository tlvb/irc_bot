loglevel=>[ #{{{
	'error',
	'warning',
	'info',
	'debug',
	'warn_unimplemented'
], # loglevel for main and plugin broker #}}}
reload_plugin_on_event_failure=>1,
reload_plugin_on_message_failure=>1,
connection=>{ #{{{
	ssl=>1,
	host=>'chat.freenode.net',
	port=>6697
}, #}}}
identity=>{ #{{{
	nick=>'IRCE',
	user=>'IRCE',
	realname=>'tlvb/IRCE'
}, #}}}
plugin_list=>[ #{{{
	'debug',
	'cap_negotiator',
	'auth',
	'ping_pong',
	'join_channel',
	'acl',
	'loader',
	'link',
	'var_glad'
], #}}}
plugin_config=>{ #{{{
	plugin_base=>{ #{{{
		loglevel=>['error', 'warning', 'info', 'debug'],
		'address_prefix'=>'.'
	}, #}}}
	debug=>{},
	cap_negotiator=>{ #{{{
		loglevel=>['error', 'warning', 'info', 'debug'],
		wait_for=>'USER-SENT',
		wanted=>['sasl', 'multi-prefix'],
		protected=>1,
	}, #}}}
	auth=>{ #{{{
		loglevel=>['error', 'warning', 'info', 'debug'],
		wait_for=>'CAP-DONE',
		administrative=>1,
		protected=>1,
		password_file=>'config/password.pl'
	}, #}}}
	ping_pong=>{ #{{{
		loglevel=>['error', 'warning'],
		wait_for=>'AUTH-DONE',
		administrative=>1,
		protected=>1,
		query_threshold=>30,
		response_threshold=>30
	}, #}}}
	join_channel=>{ #{{{
		loglevel=>['error', 'warning', 'info', 'debug'],
		wait_for=>'AUTH-DONE',
		administrative=>0,
		protected=>1,
		channels=>[
			'#varglad', '#afborgen', '#reddit-cyberpunk', '#cyberpunk'
		],
		kickrejoin=>[
			'#varglad', '#afborgen'
		]
	}, #}}}
	acl=>{ #{{{
		loglevel=>['error', 'warning', 'info', 'debug'],
		wait_for=>'AUTH-DONE',
		admins=>['tlvb'],
		blacklist_login=>[
			'ramhog' # another bot
		],
		blacklist_nick=>[
			'ramhog', # another bot
			'lardbot'
		]
	}, #}}}
	loader=>{ #{{{
		loglevel=>['error', 'warning', 'info', 'debug'],
		wait_for=>'AUTH-DONE',
		administrative=>1,
		protected=>1,
		use_acl=>1
	}, #}}}
	link=>{ #{{{
		loglevel=>['error', 'warning', 'info', 'debug'],
		wait_for=>'AUTH-DONE',
		use_acl=>1,
		min_trustlevel=>0,
	} #}}}
} #}}}
