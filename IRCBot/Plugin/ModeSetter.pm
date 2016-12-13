use warnings;
use strictures 2;
package IRCBot::Plugin::ModeSetter;
use parent 'IRCBot::Plugin::PluginBase';
use IRCBot::Message;

sub new { #{{{
	my $class = shift;

	my $self = IRCBot::Plugin::PluginBase->new(@_);
	@{$self}{qw/version/} = ('0.0.0',);
	bless $self, $class;

	return $self;

} #}}}
sub handle_message { #{{{
	my $self = shift;
	my $m = shift;
	if ($m->c eq '001') {
			$self->emit_message(
				command=>'MODE',
				params=>[
					$self->identity->{nick},
					$self->config->{modes}
				]);
	}
	return undef;
} #}}}
1;
