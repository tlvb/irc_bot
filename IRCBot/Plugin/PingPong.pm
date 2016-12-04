use warnings;
use strictures 2;
package IRCBot::Plugin::PingPong;
use parent 'IRCBot::Plugin::PluginBase';
use IRCBot::Message;
use IRCBot::DayLog;

sub new { #{{{
	my $class = shift;

	my $self = IRCBot::Plugin::PluginBase->new(@_);
	@{$self}{qw/version last_time key/} = ('0.2.0', time, '-');
	bless $self, $class;
	$self->state_change('init');

	return $self;

} #}}}
sub handle_message { #{{{
	my $self = shift;
	my $m = shift;

	if ($m->c eq '001' or $m->c eq 'PING') {
		$self->state_change('idle') if $self->{state} eq 'init';
	}

	if ($m->c eq 'PING') {
		$self->emit_message(
			command=>'PONG',
			params=>[$m->p0]);
	}
	elsif ($m->c eq 'PONG' and $self->{state} eq 'ping-sent' and grep {$self->{key} eq $_} $m->ps) {
		$self->state_change('idle');
	}

	if ($self->{state} eq 'idle') {
		$self->{last_time} = time;
	}
	return undef;
} #}}}
sub handle_timeout { #{{{
	my $self = shift;
	my $now = time;
	if ($self->{state} eq 'init') {
		$self->log_d('timeout during init phase');
		$self->emit_event(type=>'GLOBAL-RESET');
	}
	elsif ($self->{state} eq 'idle') {
		if ($now - $self->{last_time} >= $self->config->{query_threshold}) {
			$self->state_change('ping-sent');
			$self->{key} = 1000000 + int(rand(1000000));
			$self->{last_time} = $now;
			$self->emit_message(
				command=>'PING',
				params=>[$self->{key}]);
		}
	}
	elsif ($self->{state} eq 'ping-sent') {
		if ($now - $self->{last_time} >= $self->config->{response_threshold}) {
			$self->state_change('ping-quit');
			$self->{last_time} = $now;
			$self->emit_message(
				command=>'QUIT',
				params=>['server ping pong response timeout']);
		}
	}
	elsif ($self->{state} eq 'ping-quit') {
		$self->emit_event(type=>'GLOBAL-RESET');
	}
	return undef;
} #}}}
sub get_timeout { #{{{
	my $self = shift;
	my $timeout = -1;
	if ($self->{state} eq 'init') {
		$timeout =  $self->config->{query_threshold}*3 - (time - $self->{last_time});
	}
	elsif ($self->{state} eq 'idle') {
		$timeout =  $self->config->{query_threshold} - (time - $self->{last_time});
	}
	elsif ($self->{state} eq 'ping-sent' || $self->{state} eq 'ping-quit') {
		$timeout =  $self->config->{response_threshold} - (time - $self->{last_time});
	}
	return $timeout;
} #}}}

1;
