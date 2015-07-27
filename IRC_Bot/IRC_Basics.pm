use warnings;
use strict;
package IRC_Bot::IRC_Basics;
use MIME::Base64;

sub new { #{{{
	my $class = shift;
	my $ircio = shift;
	my  $self = {
		io=>$ircio,
		timeout=>0
	};
	bless $self, $class;
	return $self;
} #}}}
sub wait_exclusive { #{{{
	my $self = shift;
	print "--- INPUT IGNORED UNTIL MATCHING: [".join(' ', @_)."])\n";
	while (my $m = $self->wait_for_input(600)) {
		if (exists $m->{ERROR}) {
			print "--- ERROR $m->{ERROR}\n";
			return $m;
		}
		elsif (1 == grep {$m->{command} eq $_} @_) {
			print "--- MATCH FOUND: $m->{command}, RESUMING REGULAR OPERATIONS\n";
			return $m;
		}
	}
} #}}}
sub wait_for_input { #{{{
	my $self = shift;
	my $timeout = shift;

	INPUTWAIT: while (my $m = $self->{io}->receive($timeout)) {
		if (exists $m->{ERROR}) {
			if ($m->{ERROR} eq 'TIMEOUT') {
				if ($self->{timeout} == 0) {
					$self->{timeout} = 1+int(rand(10000));
					$self->{io}->csend('PING', $self->{timeout});
					next INPUTWAIT;
				}
				else {
					$self->{io}->csend('QUIT', 'client-server connection timeout');
					$self->{io}->reconnect();
					return {ERROR=>'RESET'};
				}
			}
			elsif ($m->{ERROR} eq 'UNDEFINED') {
				$self->{io}->reconnect();
				return {ERROR=>'RESET'};
			}
			elsif ($m->{ERROR} eq 'CLOSED') {
				$self->{io}->connect();
				return {ERROR=>'RESET'};
			}
		}
		else {
			if ($m->{command} eq 'PONG') {
				if ($m->{params}->[1] eq $self->{timeout}) {
					$self->{timeout} = 0;
					next INPUTWAIT;
				}
			}
			elsif ($m->{command} eq 'PING') {
				$self->{io}->csend('PONG', $m->{params}->[0]);
				next INPUTWAIT;
			}
		}
		return $m;
	}
} #}}}
sub init_plain_sasl_auth { #{{{
	my $self = shift;
	my $user = shift;
	my $pass = shift;
	my $m;

	$self->{io}->csend('CAP', 'REQ', 'sasl');
	$self->{io}->csend('USER', $user, '0', '*', "fred $user/bot");
	$m = $self->wait_exclusive('CAP');
	return -1 if exists $m->{ERROR};
	return -2 unless (1 == grep {uc $_ eq 'ACK'} @{$m->{params}}) and
	                 (1 == grep /sasl/i, @{$m->{params}});

	$self->{io}->csend('AUTHENTICATE', 'PLAIN');
	$m = $self->wait_exclusive('AUTHENTICATE');
	return -1 if exists $m->{ERROR};
	return -2 unless $m->{params}->[0] eq '+';

	$self->{io}->redact(1);
	$self->{io}->csend('AUTHENTICATE', MIME::Base64::encode(join("\0", ($user, $user, $pass))));
	$self->{io}->redact(0);

	$m = $self->wait_exclusive('900');
	return -1 if exists $m->{ERROR};

	$self->{io}->csend('CAP', 'END');
	$self->{user} = $user;

	return 0;
} #}}}
sub init_nick_and_ghost { #{{{
	my $self = shift;
	my $nick = shift;
	my $tmpnick = '';
	TRY_NICK: while (1) {
		my $ghost = 0;
		$self->{io}->csend('NICK', $nick);
		while (my $m = $self->wait_exclusive('001', '433', '436', 'NICK')) {
			return -1 if exists $m->{ERROR};
			if ($m->{command} eq '001') {
				return 0 unless $ghost;
				last;
			}
			elsif ($m->{command} eq 'NICK') {
				return 0 if $m->{name} eq $tmpnick and $m->{params}->[0] eq $nick;
			}
			else {
				$ghost = 1;
				$tmpnick = sprintf('TMP%04d', int(rand(1000)));
				$self->{io}->csend('NICK', $tmpnick);
			}
		}
		# ghosting it is
		$self->{io}->msg('NickServ', "ghost $nick");
		while (my $m = $self->wait_exclusive('NOTICE')) {
			if ($m->{sanitized_message} =~ /$nick has been ghosted/i) {
				next TRY_NICK;
			}
		}
	}
	return -1;
}

1;
