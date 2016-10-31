use warnings;
use strictures 2;
package IRCBot::Plugin::PluginBase;
use IRCBot::Message;
use IRCBot::Event;
use IRCBot::DayLog;

sub new { #{{{
	my $class = shift;
	my %o = @_;
	my $self = {
		config=>$o{config}//{},
		identity=>$o{identity}//{},
		version=>$o{version}//'BP/unset',
		state=>'BP/unset',
		outgoing_events=>[],
		outgoing_messages=>[],
		logcolor=>$o{logcolor}//IRCBot::DayLog::cyan(),
	};
	bless $self, $class;
	return $self;
} #}}}
sub log_ { #{{{
	my $self = shift;
	my $msg = shift;
	my $level = shift // 'info';
	if (grep {$_ eq $level} @{$self->config->{loglevel}}) {
		my $c = $self =~ s/.*::([^:=]+)(?:=.*)?/$1/r;
		IRCBot::DayLog::log([$self->{logcolor}, $c, IRCBot::DayLog::regular()], $msg);
	}
} #}}}
sub log_e { log_(@_, 'error');   }
sub log_w { log_(@_, 'warning'); }
sub log_i { log_(@_, 'info');    }
sub log_d { log_(@_, 'debug');   }
sub log_wul { log_(@_, 'warn_unimplemented');   }
sub handle_event { #{{{
	my $self = shift;
	$self->log_wul("not implemented: handle_event()");
	return undef;
} #}}}
sub decode_privmsg { #{{{
	my $self = shift;
	my $m = shift;
	my $nick = $self->identity->{nick};
	my $prefix = $self->config->{address_prefix};
	my $d = {
		addressed=>0,
		respond_target=>$m->p0,
		respond_prefix=>'',
		message=>$m->p1
	};
	if ($m->p0 eq $self->identity->{nick}) {
		$d->{addressed} = 3;
		$d->{respond_target} = $m->{name};
	}
	else {
		my ($ap, $msg) = split /[,:]?\s+/, $m->p1, 2;
		if ($ap eq $self->identity->{nick}) {
			$d->{addressed} = 2;
			$d->{respond_prefix} = $m->{name}.': ';
			$d->{message} = $msg;
		}
		if ((substr $m->p1, 0, (length $self->config->{address_prefix})) eq $self->config->{address_prefix}) {
			$d->{addressed} = 1;
			$d->{respond_prefix} = $m->{name}.': ';
			$d->{message} = substr $m->p1, length $self->config->{address_prefix};
			$d->{message} =~ s/^\s+//;
		}
	}
	return $d;
} #}}}
sub handle_message { #{{{
	my $self = shift;
	$self->log_wul("not implemented: handle_input()");
	return undef;
} #}}}
sub handle_input { #{{{
	$_[0]->log("DEPRECATED FUNCTION handle_input CALLED");
	die "deprecated function handle_input called\n";
} #}}}
sub handle_timeout { #{{{
	my $self = shift;
	$self->log_wul("not implemented: handle_timeout()");
	return undef;
} #}}}
sub version { #{{{
	my $self = shift;
	return $self->{version};
} #}}}
sub emit_event { #{{{
	my $self = shift;
	my $event = undef;
	if (@_ == 1) {
		$event = shift;
	}
	else {
		$event = IRCBot::Event->new(@_);
	}
	push @{$self->{outgoing_events}}, $event;
	$self->log_d('emitting event '.IRCBot::DayLog::yellow.$event->deflate.IRCBot::DayLog::regular);
} #}}}
sub emit_message { #{{{
	my $self = shift;
	my $message = undef;
	my $mct = undef;
	if (@_ == 1) {
		$message = shift;
		$mct = 0;
	}
	else {
		$message = IRCBot::Message->new(@_);
		$mct = 1;
	}
	if (defined $message) {
		push @{$self->{outgoing_messages}}, $message;
		my $deflated = $message->deflate;
		if (defined $deflated) {
			$self->log_d('emitting message ('.IRCBot::DayLog::cyan.($message->deflate).IRCBot::DayLog::regular.')');
		}
		elsif ($mct == 1) {
			my %h = @_;
			my $s = join ', ', "$_=>$h{$_}" for keys %h;
			$self->log_d('emitting message ('.IRCBot::DayLog::cyan.("a message created from (".$s.") deflated into undefined").IRCBot::DayLog::regular.')');
		}
		else {
			$self->log_d('emitting message ('.IRCBot::DayLog::cyan.("a message sent to emit_messagge deflated into undefined").IRCBot::DayLog::regular.')');
		}
	}
	else {
		my $msgstr = '';
		if (@_) {
			$msgstr = join ',', @_;
		}
		$self->log_e("undefined message ($msgstr)");
	}
} #}}}
sub get_events { #{{{
	my $self = shift;
	my @events = @{$self->{outgoing_events}};
	$self->{outgoing_events} = [];
	return @events;
} #}}}
sub get_messages { #{{{
	my $self = shift;
	my @messages = @{$self->{outgoing_messages}};
	$self->{outgoing_messages} = [];
	return @messages;
} #}}}
sub get_timeout { #{{{
	my $self = shift;
	$self->log_wul("not implemented: get_timeout()");
	return -1;
} #}}}
sub state_change { #{{{
	my $self = shift;
	my $old = $self->{state};
	$self->{state} = shift;
	$self->log_d(IRCBot::DayLog::yellow()."state change $old -> $self->{state}".IRCBot::DayLog::regular());
} #}}}
sub condense { #{{{
	my $self = shift;
	return undef;
} #}}}
sub evaporate { #{{{
	my $self = shift;
} #}}}
sub config { return $_[0]->{config}; }
sub identity { return $_[0]->{identity}; }
1;
