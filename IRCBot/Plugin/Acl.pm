use warnings;
use strictures 2;
package IRCBot::Plugin::Acl;
use parent 'IRCBot::Plugin::PluginBase';
use IRCBot::Message;
use IRCBot::DayLog;
sub new { #{{{
	my $class = shift;

	my $self = IRCBot::Plugin::PluginBase->new(@_);
	@{$self}{qw/version acl chan_sigils umode_sigils mode_extractor freezer freezerlock monitored_channels/} = ( #{{{
		'0.4.0-beta-0',
		{},
		['#'],
		{'@'=>'o', '+'=>'v'},
		qr/([+@]*)(.*)/,
		{},
		{},
		[]
	); #}}}
	bless $self, $class;

	return $self;

} #}}}
sub handle_event { #{{{
	my $self = shift;
	my $event = shift;

	$self->log_d("handling event ".$event->deflate);

	if ($event->type eq 'ACL-QUERY') {
		my $nick = $event->{nick};
		if (exists $self->{acl}->{$nick} && exists $self->{acl}->{$nick}->{channel}) {
			if ($self->{acl}->{$nick}->{trust} > -1000) {
				$self->respond($event);
			}
			else {
				$self->freeze($nick, $event);
				$self->emit_message(
					command=>'PRIVMSG',
					params=>['NickServ', "ACC $nick *"]);
			}
		}
		else {
			$self->freeze($nick, $event);
			$self->wipe_slate($nick);
			$self->emit_message(
				command=>'WHOIS',
				params=>[$nick]);
		}
	}
} #}}}
sub respond { #{{{
	my $self = shift;
	my $event = shift;
	my $nick = $event->{nick};
	my $forcetrust = shift;
	my $aclent = undef;
	if (exists $self->{acl}->{$nick}) {
		$aclent = $self->{acl}->{$nick};
		for my $k (sort keys %$aclent) {
			my $vs = '';
			if (ref $aclent->{$k} eq 'ARRAY') {
				$vs .= '[ '.(join ', ', @{$aclent->{$k}}).' ]';
			}
			elsif (ref $aclent->{$k} eq 'HASH') {
				$vs .= '{';
				for (sort keys %{$aclent->{$k}}) {
					$vs .= "$_=>'$aclent->{$k}->{$_}'";
				}
				$vs .= ' }';
			}
			else {
				$vs = "'$aclent->{$k}'";
			}
			$self->log_d("$k=>$vs")
		}
	}
	$aclent //= {};
	if (defined $forcetrust) {
		$aclent = {trust=>$forcetrust};
	}
	$self->log_d('trust is '.($aclent->{trust}//'UNDEF'));
	$self->emit_event(
		type=>'ACL-RESPONSE',
		origin=>'acl',
		target=>$event->origin,
		nick=>$nick,
		acl_data=>$aclent,
		data=>$event->{data}
	);
} #}}}
sub init_nick { #{{{
	my $self = shift;
	my $nick = shift;
	if (not exists $self->{acl}->{$nick}) {
		$self->{acl}->{$nick} = { trust=>-1000 };
		# -1000 uninitialized should not be seen outside the plugin
		# -20 not online and not registered
		# -10 not online
		# -2 explicitly blacklisted by nick
		# -1 explicitly blacklisted by login, e.g. so as to not respond to other bots etc
		# 0 unknown/not identified
		# 1 identified with nickserv
		# 2 identified with nickserv and administrative access
	}
} #}}}
sub finalize_nick_data { #{{{
	my $self = shift;
	my $nick = shift;
	if ($self->{acl}->{$nick}->{trust} == -1000) {
		$self->{acl}->{$nick}->{trust} = 0;
	}
} #}}}
sub set_modes { #{{{
	my $self = shift;
	my $nick = shift;
	my $channel = shift;
	my $modes = shift;
	my $modestr = join ',', @{$modes};
	$self->init_nick($nick);
	$self->{acl}->{$nick}->{channel} = {} unless exists $self->{acl}->{$nick}->{channel};
	$self->{acl}->{$nick}->{channel}->{$channel} = $modes;
} #}}}
sub add_mode { #{{{
	my $self = shift;
	my $nick = shift;
	my $channel = shift;
	my $mode = shift;
	$self->{acl}->{$nick}->{channel} = {} unless exists $self->{acl}->{$nick}->{channel};
	$self->{acl}->{$nick}->{channel}->{$channel} = [ $mode, grep { $_ ne $mode } @{$self->{acl}->{channel}->{$channel}} ];
	$self->log_d("adding mode $mode to $nick in $channel for result ".(join ',', @{$self->{acl}->{channel}->{$channel}}));
} #}}}
sub sub_mode { #{{{
	my $self = shift;
	my $nick = shift;
	my $channel = shift;
	my $mode = shift;
	$self->{acl}->{$nick}->{channel} = {} unless exists $self->{acl}->{$nick}->{channel};
	$self->{acl}->{$nick}->{channel}->{$channel} = [ grep { $_ ne $mode } @{$self->{acl}->{channel}->{$channel}} ];
	$self->log_d("removing mode $mode from $nick in $channel for result ".(join ',', @{$self->{acl}->{channel}->{$channel}}));
} #}}}
sub add_monitor { #{{{
	my $self = shift;
	my $channel = shift;
	push @{$self->{monitored_channels}}, $channel;
} #}}}
sub purge_monitor { #{{{
	my $self = shift;
	my $channel = shift;
	@{$self->{monitored_channels}} = grep {$_ ne $channel} @{$self->{monitored_channels}};
	for (keys %{$self->{acl}}) {
		$self->rem_channel_entry($_, $channel);
	}
} #}}}
sub rem_channel_entry { #{{{
	my $self = shift;
	my $nick = shift;
	my $channel = shift;
	delete $self->{acl}->{$nick}->{channel}->{$channel} if exists $self->{acl}->{$nick}->{channel}->{$channel};
	$self->log_d("deleting acl information for user $nick regarding channel $channel");
	if (0 == keys %{$self->{acl}->{$nick}->{channel}}) {
		$self->wipe_slate($nick);
	}
} #}}}
sub wipe_slate { #{{{
	my $self = shift;
	my $nick = shift;
	delete $self->{acl}->{$nick} if exists $self->{acl}->{$nick};
	$self->log_d("deleting all acl information for user $nick");
} #}}}
sub update_auth { #{{{
	my $self = shift;
	my $nick = shift;
	my $login = shift;

	$self->init_nick($nick);
	if (!defined $login || $login eq '*' || $login eq '') {
		# untrusted
		$self->{acl}->{$nick}->{login} = '';
		if (scalar grep {$_ eq $nick} @{$self->config->{blacklist_nick}}) {
			$self->{acl}->{$nick}->{trust} = -2;
		}
		else {
			$self->{acl}->{$nick}->{trust} = 0;
		}	
	}
	else {
		$self->{acl}->{$nick}->{login} = $login;
		if (scalar grep {$_ eq $nick} @{$self->config->{blacklist_nick}}) {
			$self->{acl}->{$nick}->{trust} = -2;
		}
		elsif (scalar grep {$_ eq $login} @{$self->config->{admins}}) {
			# identified with nickserv and administrative access
			$self->{acl}->{$nick}->{trust} = 2;
		}
		elsif (scalar grep {$_ eq $login} @{$self->config->{blacklist_login}}) {
			# identified with nickserv and blacklisted
			# e.g. to not get in a shouting match with another bot
			$self->{acl}->{$nick}->{trust} = -1;
		}
		else {
			# identified with nickserv but not administrative access
			$self->{acl}->{$nick}->{trust} = 1;
		}
	}
} #}}}
sub rename { #{{{
	my $self = shift;
	my $old = shift;
	my $new = shift;
	if (exists $self->{acl}->{$old}) {
		$self->{acl}->{$new} = delete $self->{acl}->{$old};
		$self->log_d("user changed nick from $old to $new");
	}
} #}}}
sub handle_message { #{{{
	my $self = shift;
	my $m = shift;
#{{{
=comment
	>>> :card.freenode.net 311 tlvb|dev tlvb ~tlvb unaffiliated/tlvb * :tlvb
	>>> :card.freenode.net 312 tlvb|dev tlvb hitchcock.freenode.net :Sofia, BG, EU
	>>> :card.freenode.net 671 tlvb|dev tlvb :is using a secure connection
=cut
#}}}
	if ($m->c eq '005' && $m->p0 eq $self->identity->{nick}) { #{{{
		# CHANTYPES=\S+
		# PREFIX=(ov)@+
		for ($m->ps) {
			if (/CHANTYPES=(\S+)/) {
				$self->{chan_sigils}=[split '', $1];
			}
			if (/PREFIX=\(([^)]+)\)(\S+)/) {
				$self->{umode_sigils} = {};
				my @mode = split '', $1;
				my @prefix = split '', $2;
				@{$self->{umode_sigils}}{@prefix} = @mode;
				my $matcher = '(['.(join '', @prefix).']*)(.*)';
				$self->{mode_extractor} = qr/$matcher/;
			}
		}
	} #}}}
	elsif ( # NOTICE nickserv acc reply #{{{
		$m->c eq 'NOTICE'
		and $m->{prefix} eq 'NickServ!NickServ@services.'
		and $m->p0 eq $self->identity->{nick}
	) {
		$self->log_d($m->{sanitized_message});
		if ($m->{sanitized_message} =~ /^(\S+) -> (\S+) ACC (\d+)(?:\s|$)/) {
			# somenick -> someaccount ACC 3
			# somenick -> * ACC 0 (not registered)
			my $nick = $1;
			my $nsacc = $2;
			$self->log_d($nick.' has NickServ account status '.$3.'/'.$nsacc);
			$self->update_auth($nick, $nsacc);
			if ($self->has_frozen($nick)) {
				my @thawed = $self->thaw($nick);
				$self->respond($_) for @thawed;
			}
		}
		elsif ($m->{sanitized_message} =~ /^(\S+) is not registered/) {
			my $nick = $1;
			$self->log_d($nick.' is not a registered nick');
			$self->unlock_freezer($nick);
			if ($self->has_frozen($nick)) {
				$self->log_d("processing thawed event for $nick.");
				my @thawed = $self->thaw($nick);
				$self->respond($_, -20) for @thawed;
			}
		}
		elsif ($m->{sanitized_message} =~ /Information on (\S+)/) {
			my $nick = $1;
			$self->log_d($nick.' is registered, but not online');
			$self->unlock_freezer($nick);
			if ($self->has_frozen($nick)) {
				$self->log_d("processing thawed event for $nick.");
				my @thawed = $self->thaw($nick);
				$self->respond($_, -10) for @thawed;
			}
		}
	} #}}}
	elsif ($m->c eq '353') { # RPL_NAMREPLY #{{{
		#>>> :hitchcock.freenode.net 353 tlvb-a @ #afborgen :tlvb-a @tlvb|m otheruser cheese-man kevin
		#                            c   p0     p1 p2       p3
		my $channel = undef;
		my @names = ();
		if ($m->p1 =~ /[=*@]/) { # RFC 2812 mode #{{{
			# 353 self [=*@] channel :[+@]*nick [+@]*nick...
			# c   p0   p1    p2      p3
			$channel = $m->p2;
			@names = split /\s+/, $m->p3;
		} #}}}
		else { # RFC 1459 mode #{{{
			# 353 self channel :[+@]?nick [+@]?nick...
			# c   p0   p1      p2
			$channel = $m->p1;
			@names = split /\s+/, $m->p2;
		} #}}}
		for (@names) {
			$_ =~ $self->{mode_extractor};
			$self->set_modes($2, $channel, [ map {$self->{umode_sigils}->{$_}} split '', $1 ]);
		}
	} #}}}
	elsif ($m->c eq '319') { # RPL_WHOISCHANNELS #{{{
		#>>> :card.freenode.net 319 tlvb|dev tlvb :@#afborgen @+#otherchannel
		#                       c   p0       p1    p2
		for my $scpair (split /\s+/, $m->p2) {
			$scpair =~ $self->{mode_extractor};
			my $sigils = $1;
			my $channel = $2;
			next unless grep {$channel eq $_} @{$self->{monitored_channels}};
			my $modes = [ map {$self->{umode_sigils}->{$_}} split '', $sigils ];
			$self->set_modes($m->p1, $channel, $modes);
		}
	} #}}}
	elsif ($m->c eq '330') { # RPL_WHOISACCOUNT #{{{
		#>>> :card.freenode.net 330 tlvb|dev tlvb tlvb :is logged in as
		#                       c   p0       p1   p2   p3
		#                                    nick authname
		$self->log_d($m->p1.' is identified with NickServ as '.$m->p2);
		$self->update_auth($m->p1, $m->p2);
	} #}}}
	elsif ($m->c eq '366') { # RPL_ENDOFNAMES #{{{
		if ($m->p0 eq $self->identity->{nick}) {
			my $chan = $m->p1;
		}
	} #}}}
	elsif ($m->c eq '318') { # RPL_ENDOFWHOIS #{{{
		# >>> :card.freenode.net 318 tlvb|dev tlvb :End of /WHOIS list.
		#                        c   p0       p1   p2
		#                            self     nick foobar
		$self->init_nick($m->p1);
		$self->finalize_nick_data($m->p1);
		my @thawed = $self->thaw($m->p1);
		$self->respond($_) for @thawed;
	} #}}}
	elsif ($m->c eq '401') { # RPL_NOSUCHNICK #{{{
		#401 irce|dev tlvb :No such nick/channel
		$self->lock_freezer($m->p1);
		$self->wipe_slate($m->p1);
		$self->emit_message(
			command=>'PRIVMSG',
			params=>['NickServ', "INFO ".$m->p1]);
	} #}}}
	elsif ($m->c eq 'MODE') { # handle mode changes? #{{{
		my $type = 'user';
		for my $cs (@{$self->{chan_sigils}}) {
			if ($cs eq substr $m->p0, 0, 1) {
				$type = 'channel';
			}
		}
		if ($type eq 'user') { #{{{
			my $nick = $m->p0;
			my $command_index = 1;
			while ($command_index <= $m->nps) {
				my $param_index = $command_index+1;
				for my $comm (split '', ($m->ps)[$command_index]) {
					next if $comm =~ /[+-]/;
					$self->log_d("ignoring user mode change $comm");
				}
				$command_index = $param_index;
			}
		} #}}}
		elsif ($type eq 'channel') { #{{{
			my $channel = $m->p0;
			my $command_index = 1;
			my $modify_mode = 'add_mode';
			while ($command_index <= $m->nps) { #{{{
				my $param_index = $command_index+1;
				$self->log_d("channel is $channel, mode string is ".(($m->ps)[$command_index]));
				for my $comm (split '', ($m->ps)[$command_index]) { #{{{
					if ($comm eq '+') {
						$modify_mode = 'add_mode';
						$self->log_d("adding flags");
					}
					elsif ($comm eq '-') {
						$modify_mode = 'sub_mode';
						$self->log_d("removing flags");
					}
					elsif ('Oov' =~ /$comm/)  {
						# O - give "channel creator" status;
						# o - give/take channel operator privilege;
						# v - give/take the voice privilege;
						$self->$modify_mode(($m->ps)[$param_index], $channel, $comm);
						$param_index += 1;
					}
					elsif ('aimnqpsrt' =~ /$comm/) {
						# we don't currently care about these, and they don't consume any parameters

						# a - toggle the anonymous channel flag;
						# i - toggle the invite-only channel flag;
						# m - toggle the moderated channel;
						# n - toggle the no messages to channel from clients on the
						#     outside;
						# q - toggle the quiet channel flag;
						# p - toggle the private channel flag;
						# s - toggle the secret channel flag;
						# r - toggle the server reop channel flag;
						# t - toggle the topic settable by channel operator only flag;
						#
						# Z - freenode? secure connection thing
						$self->log_d("ignoring channel mode change $comm");
					}
					elsif ('klbeI' =~ /$comm/) {
						# we don't care about these, but they still consume a parameter
						# sometimes the parameter can be elided when sending to a server
						# though, but that is not a case we are covering here

						# k - set/remove the channel key (password);
						# l - set/remove the user limit to channel;
						#
						# b - set/remove ban mask to keep users out;
						# e - set/remove an exception mask to override a ban mask;
						# I - set/remove an invitation mask to automatically override
						#     the invite-only flag;
						$self->log_d("ignoring channel mode change $comm with parameter".$m->ps->[$param_index]);
						$param_index +=1;
					}
					else {
						$self->log_d("ignoring UNKNOWN channel mode change $comm");
					}
				} #}}}
				$command_index = $param_index;
			} #}}}
		} #}}}
	} #}}}
	elsif ($m->c eq 'JOIN') { #{{{
		if ($m->{name} eq $self->identity->{nick}) {
			# we are joining a channel
			$self->log_d('we joined '.$m->p0);
			$self->add_monitor($m->p0);
		}
	} #}}}
	elsif ($m->c eq 'PART') { #{{{
		if ($m->{name} ne $self->identity->{nick}) {
			# somebody else is leaving a channel we monitor
			$self->log_d($m->{name}.' left channel '.$m->p0);
			$self->rem_channel_entry($m->{name}, $m->p0);
		}
		else {
			# we are leaving a channel
			$self->log_d('we parted channel '.$m->p0);
			$self->purge_monitor($m->p0);
		}
	} #}}}
	elsif ($m->c eq 'QUIT') { # handle when someone leaves #{{{
		$self->log_d($m->{name}.' quit');
		$self->wipe_slate($m->{name});
	} #}}}
	elsif ($m->c eq 'NICK') { #{{{
		if ($m->{name} ne $self->identity->{nick}) {
			$self->log_d($m->{name}.' changed nick to '.$m->p0);
			$self->rename($m->{name}, $m->p0);
		}
	} #}}}
	#elsif ($m->c eq 'KICK') { #{{{
	# not neccessary, since kick causes part
	#	$self->rem_channel_entry($m->{name}, $m->p0);
	#} #}}}
} #}}}
sub freeze { #{{{
	my $self = shift;
	my $key = shift;
	my $value = shift;
	$self->log_d("freezing a value with key $key");
	$self->{freezer}->{$key} = [] unless exists $self->{freezer}->{$key};
	push @{$self->{freezer}->{$key}}, $value;
} #}}}
sub has_frozen { return exists $_[0]->{freezer}->{$_[1]}; }
sub thaw { #{{{
	my $self = shift;
	my $key = shift;
	$self->log_d("thawing values with key $key");
	return () unless exists $self->{freezer}->{$key} and not exists $self->{freezerlock}->{$key};
	return @{ scalar delete $self->{freezer}->{$key} };
} #}}}
sub lock_freezer {
	my $self = shift;
	my $key = shift;
	$self->log_d("locking freezer entries with key  $key");
	$self->{freezerlock}->{$key} = 1;
}
sub unlock_freezer {
	my $self = shift;
	my $key = shift;
	$self->log_d("unlocking freezer entries with key  $key");
	delete $self->{freezerlock}->{$key};
}

1;
