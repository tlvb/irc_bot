use warnings;
use strictures 2;
package IRCBot::Plugin::Auth;
use parent 'IRCBot::Plugin::PluginBase';
use IRCBot::ConfigReader;
use IRCBot::Message;
use MIME::Base64;

sub new { #{{{
	my $class = shift;

	my $self = IRCBot::Plugin::PluginBase->new(@_);
	@{$self}{qw/version auth_mode ghost_timestamp/} =
	            ('0.2.3-debug2', 'undecided', -1);
	bless $self, $class;

	my $pwconf = IRCBot::ConfigReader::read($self->config->{password_file});
	$self->{password} = $pwconf->{password};

	if (exists $self->config->{wait_for} && $self->config->{wait_for} eq 'CAP-DONE') {
		$self->auth_mode_change('sasl');
		$self->state_change('dormant');
	}
	else {
		$self->auth_mode_change('nickserv');
		$self->state_change('nick');
		$self->emit_message(
			command=>'NICK',
			params=>[$self->identity->{nick}]);
	}
	return $self;
} #}}}
sub get_timeout {
	my $self = shift;
	if ($self->{ghost_timestamp} != -1) {
		my $to = $self->{ghost_timestamp} - time;
		if ($to < 0) {
			$self->log_d("ghost_timestamp is NOW");
			$self->handle_timout();
			$to = -1;
		}
		else {
			$self->log_d("ghost_timestamp is $to seconds in the future");
		}
		return $to;
	}
	return -1;
}
sub handle_timout {
	# use of timeout so  far: no reply from ghosting a nick
	my $self = shift;
	if ($self->{state} eq 'ghost') {
		$self->log_d("handling ghost timeout");
		$self->emit_message(
			command=>'NICK',
			params=>[$self->identity->{nick}]);
		$self->state_change('nick');
		$self->{ghost_timestamp} = -1;
	}
}
sub handle_event { #{{{
	my $self = shift;
	my $e = shift;
	if ($self->{auth_mode} eq 'sasl' && $e->type eq 'CAP-DONE') { #{{{
		if (grep {lc $_ eq 'sasl'} @{$e->{enabled}}) { #{{{
			$self->state_change('authenticate-0');
			$self->emit_message(
				command=>'AUTHENTICATE',
				params=>['PLAIN']);
		} #}}}
		else { #{{{
			$self->auth_mode_change('nickserv');
			$self->state_change('nick');
			$self->emit_message(
				command=>'NICK',
				params=>[$self->identity->{nick}]);
		} #}}}
	} #}}}
} #}}}
sub handle_message { #{{{
	my $self = shift;
	my $m = shift;
	my @pars = map {lc} $m->ps;
	my $state = $self->{state};
	my $mode = $self->{auth_mode};
	my @requested_caps = ();

	if ($state eq 'authenticate-0') { #{{{
		if ($m->c eq 'AUTHENTICATE' && $m->p0 eq '+') {
			my $u = $self->identity->{user};
			my $p = $self->{password};
			my $uup = MIME::Base64::encode(join "\0", $u, $u, $p);
			$self->state_change('authenticate-1');
			$self->emit_message(
				command=>'AUTHENTICATE',
				params=>[$uup]);
		}
	} #}}}
	elsif ($state eq 'authenticate-1') { #{{{
		if ($m->c =~ /90[0-9]/) { # logged in / sasl success or something else
			$self->emit_message(
				command=>'NICK',
				params=>[$self->identity->{nick}]);
			$self->state_change('nick');
			if ($m->c ne '900' && $m->c ne '903') {
				$self->auth_mode_change('nickserv');
			}
		}
	} #}}}
	elsif ($state eq 'nick' || $state eq 'random') { #{{{
		if ($m->c eq '433') { # nick already in use #{{{
			$self->emit_message(
				command=>'NICK',
				params=>[sprintf 'tmp%04d', int(rand(1000))]);
			$self->state_change('random');
		} #}}}
		elsif ($m->c eq '001') { #{{{
			if ($state eq 'nick') { #{{{
				if ($mode eq 'sasl') {
					# at this point we are both authed, as well as have the
					# nick we want
					$self->state_change('dormant');
					$self->emit_event(origin=>'auth', target=>'*', type=>'AUTH-DONE');
				}
				elsif ($mode eq 'nickserv') {
					$self->emit_message(
						command=>'PRIVMSG',
						params=>[
							'NickServ',
							"identify $self->identity->{nick} $self->{password}"
						]);
					$self->state_change('identify');
				}
			} #}}}
			if ($state eq 'random') { #{{{
				# if using sasl we have already authed at this point, and a password
				# is not needed, on the other hand, if nickserv is used for auth
				# we need to send the password
				if ($mode eq 'sasl') {
					$self->emit_message(
						command=>'PRIVMSG',
						params=>[
							'NickServ',
							"ghost ".$self->identity->{nick}]);
				}
				elsif ($mode eq 'nickserv') {
					$self->emit_message(
						command=>'PRIVMSG',
						params=>[
							'NickServ',
							"ghost ".$self->identity->{nick}." ".$self->{password}]);
				}
				$self->{ghost_timestamp} = time + 10;
				$self->log_d("attempting ghosting, with timestamp ten seconds in the future ".$self->{ghost_timestamp});
				$self->state_change('ghost')
			} #}}}
		} #}}}
	} #}}}
	elsif ($state eq 'ghost') { #{{{
		if ($m->c eq 'NOTICE' && $m->{prefix} eq 'NickServ!NickServ@services.') {
			$self->{ghost_timestamp} = -1;
			$self->log_d("inactivating ghost timestamp");
			if ($m->p1 =~ /has been ghosted/i) {
				$self->emit_message(
					command=>'NICK',
					params=>[$self->identity->{nick}]);
				$self->state_change('nick');
			}
			elsif ($m->p1 =~ /invalid password/i) {
				$self->state_change('failed');
				die 'invalid password';
			}
		}
	} #}}}
	elsif ($state eq 'identify') { #{{{
		if ($m->c eq 'NOTICE' && $m->{prefix} eq 'NickServ!NickServ@services') {
			if ($m->p1 =~ /you are now identified/i) {
				$self->state_change('done');
			}
			elsif ($m->p1 =~ /invalid password/i) {
				$self->state_change('failed');
				die 'invalid password';
			}
		}
	} #}}}
} #}}}
sub auth_mode_change { #{{{
	my $self = shift;
	my $old = $self->{auth_mode};
	$self->{auth_mode} = shift;
	$self->log_d("mode change $old -> $self->{auth_mode}");
} #}}}
1;
