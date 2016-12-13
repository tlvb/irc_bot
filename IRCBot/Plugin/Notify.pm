use warnings;
use strictures 2;
package IRCBot::Plugin::Notify;
use parent 'IRCBot::Plugin::PluginBase';
use IRCBot::Event;
use IRCBot::Message;
use HTML::Entities;

sub new { #{{{
	my $class = shift;

	my $self = IRCBot::Plugin::PluginBase->new(@_);
	@{$self}{qw/version watchlist pingback/} = ('0.0.0-beta-0', {}, {});
	bless $self, $class;

	return $self;

} #}}}
sub add_watchlist_entry_for {
	my $self = shift;
	my $fromwho = shift;
	my $targetwho = shift;
	my $message = shift;
	$self->log_d("add_watchlist_entry <$fromwho> <$targetwho> <$message>");
	if (not exists $self->{watchlist}->{$targetwho}) {
		$self->{watchlist}->{$targetwho} = {};
	}
	$self->{watchlist}->{$targetwho}->{$fromwho} = $message;
}
sub remove_watchlist_entry_for {
	my $self = shift;
	my $fromwho = shift;
	my $targetwho = shift;
	$self->log_d("remove_watchlist_entry <$fromwho> <$targetwho>");
	if (exists $self->{watchlist}->{$targetwho}) {
		if (exists $self->{watchlist}->{$targetwho}->{$fromwho}) {
			delete $self->{watchlist}->{$targetwho}->{$fromwho};
		}
		if (not keys %{$self->{watchlist}->{$targetwho}}) {
			delete $self->{watchlist}->{$targetwho};
		}
	}
}
sub any_watchlist_entries_for {
	my $self = shift;
	my $targetwho = shift;
	$self->log_d("any_watchlist_entries_for <$targetwho>");
	return exists $self->{watchlist}->{$targetwho};
}
sub get_watchlist_entries_for {
	my $self = shift;
	my $targetwho = shift;
	$self->log_d("get_watchlist_entries_for <$targetwho>");
	my $entries = {};
	return $self->{watchlist}->{$targetwho} // {};
}
sub add_pingback_entry_for {
	my $self = shift;
	my $target = shift;
	my $who = shift;
	$self->log_d("add_pingback_entry_for <$target> <$who>");
	if (not exists $self->{pingback}->{$target}) {
		$self->{pingback}->{$target} = [];
	}
	push @{$self->{pingback}->{$target}}, $who;
}
sub get_and_remove_pingback_entries_for {
	my $self = shift;
	my $target = shift;
	my $who = shift;
	$self->log_d("get_and_remove_pingback_entries_for <$target>");
	my $entries = [];
	if (exists $self->{pingback}->{$target}) {
		$entries = delete $self->{pingback}->{$target};
	}
	return $entries;
}
sub any_pingback_entries_for {
	my $self = shift;
	my $target = shift;
	$self->log_d("any_pingback_entries_for <$target>");
	return exists $self->{pingback}->{$target};
}
	
sub handle_event { #{{{
	my $self = shift;
	my $e = shift;
	$self->log_d($e->deflate);
	if ($e->type eq 'ACL-RESPONSE') {
		my $data = $e->{data};
		if ($data->{querytype} == 0) {
			# query response for the requester when the request is made
			if (defined $e->{acl_data}) {
				if ($e->{acl_data}->{trust} >= 1) {
					# check the status of the target
					$data->{querytype} = 1;
					$self->emit_event(target=>'acl', origin=>'notify', type=>'ACL-QUERY', nick=>$data->{targetwho}, data=>$data);
				}
			}
		}
		elsif ($data->{querytype} == 1) {
			# query response for the target when the request is made
			if (not defined $e->{acl_data}) {
				# no such user online, all right!
				$self->add_watchlist_entry_for($data->{fromwho}, $data->{targetwho}, $data->{message});
				my $response = 'I will notify you if I see '.$data->{targetwho};
				if ($data->{message} ne '') {
					$response .= ' and also relay your message';
				}
				$self->emit_message(
					command=>'PRIVMSG',
					params=>[$data->{parsed}->{respond_target}, $response.'.']);
			}
			elsif ($e->{acl_data}->{trust} >= 1) {
				$self->emit_message(
					command=>'PRIVMSG',
					params=>[$data->{parsed}->{respond_target}, $data->{parsed}->{respond_prefix}.'User '.$data->{targetwho}.' already online and logged in.']);
			}
		}
		elsif ($data->{querytype} == 2) {
			# query response for the target when the target is observed
			if (defined $e->{acl_data}) {
				if ($e->{acl_data}->{trust} >= 1) {
					my $watchlist_entries = $self->get_watchlist_entries_for($e->{nick});
					for my $fromwho (keys %$watchlist_entries) {
						my $message = $watchlist_entries->{$fromwho};
						if ($message ne '') {
							$self->emit_message(
								command=>'PRIVMSG',
								params=>[$e->{nick}, 'User '.$e->{nick}.' asked me to relay the following message:']);
							$self->emit_message(
								command=>'PRIVMSG',
								params=>[$e->{nick}, $message]);
						}
						$self->remove_watchlist_entry_for($fromwho, $e->{nick});
						$self->add_pingback_entry_for($fromwho, $e->{nick});
					}
				}
			}
		}
		elsif ($data->{querytype} == 3) {
			# pingback response 
			if (defined $e->{acl_data}) {
				if ($e->{acl_data}->{trust} >= 1) {
					my $pingback_entries = $self->get_and_remove_pingback_entries_for($e->{nick});
					$self->emit_message(
						command=>'PRIVMSG',
						params=>[$e->{nick}, "The following users that you have asked to be notified about have been observed:"]);
					$self->emit_message(
						command=>'PRIVMSG',
						params=>[$e->{nick}, join(', ', @$pingback_entries)]);
				}
			}
		}
	}
} #}}}
sub handle_message { #{{{
	my $self = shift;
	my $m = shift;
	if ($m->c eq 'PRIVMSG') {
		my $p = $self->decode_privmsg($m);
		if ($p->{addressed} > 0) {
			my ($comm, $rest) = split /\s+/, $p->{message}, 2;
			$self->log_d("got a <$comm> message with rest <".($rest//'').">");
			if ($comm eq 'notify') {
				my ($who, $what) = split /\s+/, $rest, 2;
				$self->emit_event(target=>'acl', origin=>'notify', type=>'ACL-QUERY', nick=>$m->{name}, data=>{
					parsed=>$p, querytype=>0, comm=>$comm, fromwho=>$m->{name}, targetwho=>$who, message=>$what//''});
			}
		}
		if ($self->any_watchlist_entries_for($m->{name})) {
			$self->emit_event(target=>'acl', origin=>'notify', type=>'ACL-QUERY', nick=>$m->{name}, data=>{
				querytype=>2});
		}
		if ($self->any_pingback_entries_for($m->{name})) {
			$self->emit_event(target=>'acl', origin=>'notify', type=>'ACL-QUERY', nick=>$m->{name}, data=>{
				querytype=>3});
		}
	}
} #}}}
1;

