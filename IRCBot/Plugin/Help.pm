use warnings;
use strictures 2;
package IRCBot::Plugin::Help;
use parent 'IRCBot::Plugin::PluginBase';
use IRCBot::Event;
use IRCBot::Message;
use HTML::Entities;

sub new { #{{{
	my $class = shift;

	my $self = IRCBot::Plugin::PluginBase->new(@_);
	@{$self}{qw/version/} = ('0.0.0-alpha-0');
	bless $self, $class;

	return $self;

} #}}}
sub handle_message { #{{{
	my $self = shift;
	my $m = shift;
	if ($m->c eq 'PRIVMSG') {
		my $p = $self->decode_privmsg($m);
		if ($p->{addressed} > 0) {
			if ($p->{message} eq 'help') {
			$self->emit_message(
				command=>'PRIVMSG',
				params=>[$p->{respond_target}, $p->{respond_prefix}."you can find the documentation at ".$self->config->{help_url}]);
			}
		}
	}
} #}}}
1;

