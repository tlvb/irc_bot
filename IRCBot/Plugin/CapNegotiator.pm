use warnings;
use strictures 2;
package IRCBot::Plugin::CapNegotiator;
use parent 'IRCBot::Plugin::PluginBase';
use IRCBot::Message;

sub new { #{{{
	my $class = shift;

	my $self = IRCBot::Plugin::PluginBase->new(@_);
	@{$self}{qw/version/} = ('0.1.0',);

	bless $self, $class;
	$self->state_change('dormant');
	return $self;
} #}}}
sub handle_event { #{{{
	my $self = shift;
	my $e = shift;
	if ($e->type eq $self->config->{wait_for}) {
		$self->emit_message(
			command=>'CAP',
			params=>['LS']);
		$self->state_change('cap-ls');
	}
} #}}}
sub handle_message { #{{{
	my $self = shift;
	my $m = shift;
	my $state = $self->{state};

	if ($state eq 'cap-ls' && $m->c eq 'CAP' && uc $m->p1 eq 'LS') { #{{{
		my @requested = ();
		my @supported = map lc, split /\s+/, $m->p2;
		for my $wc (@{$self->config->{wanted}}) {
			push @requested, $wc if grep {$wc eq $_} @supported;
		}
		$self->emit_message(
			command=>'CAP',
			params=>[
				'REQ',
				join ' ', @requested]);
		$self->state_change('cap-req');
	} #}}}
	elsif ($state eq 'cap-req' && $m->c eq 'CAP' && ( uc $m->p1 eq 'ACK' || uc $m->p1 eq 'NAK')) { #{{{
		$self->emit_message(
			command=>'CAP',
			params=>['END']);
		my @enabled = ();
		@enabled = map lc, split /\s+/, $m->p2 if uc $m->p1 eq 'ACK';
		$self->emit_event(
			origin=>'cap_negotiator',
			type=>'CAP-DONE',
			enabled=>\@enabled);
		$self->state_change('dormant');
	} #}}}
} #}}}
1;

