use warnings;
use strictures 2;
package IRCBot::Plugin::JoinChannel;
use parent 'IRCBot::Plugin::PluginBase';
use IRCBot::Message;

sub new { #{{{
	my $class = shift;

	my $self = IRCBot::Plugin::PluginBase->new(@_);
	@{$self}{qw/version/} = ('0.1.0',);
	bless $self, $class;

	return $self;

} #}}}
sub handle_message { #{{{
	my $self = shift;
	my $m = shift;

	if ($m->c eq '001') {
		for (@{$self->config->{channels}}) {
			$self->emit_message(
				command=>'JOIN',
				params=>[$_]);
		}
	}
	elsif ($m->c eq 'KICK') {
		if (grep {$m->p0 =~ /$_/} @{$self->config->{kickrejoin}}) {
			$self->emit_message(
				command=>'JOIN',
				params=>[$m->p0]);
		}
	}
	return undef;
} #}}}
1;
