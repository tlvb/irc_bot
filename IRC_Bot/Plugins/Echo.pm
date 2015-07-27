use warnings;
use strict;
package IRC_Bot::Plugins::Echo;

sub new {
	my $class = shift;
	my $self = {};
	bless $self, $class;
	return $self;
}
sub handle_input {
	my $self = shift;
	my $m = shift;
	my $mynick = shift;
	my @ret = ();

	if (@_) {
		# ( trg who comm params... )
		if (lc $_[2] eq 'echo') {
			push @ret, ['PRIVMSG', $_[0], "$_[1]: $_[3]"];
		}
		elsif (lc $_[2] eq 'help' and lc $_[3] eq 'echo') {
			push @ret, ['PRIVMSG', $_[0], "$_[1]: .echo SOMESTRING -- repeats a string"];
		}
	}
	return @ret;
}
1;
