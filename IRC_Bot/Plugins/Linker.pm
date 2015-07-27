use strict;
use warnings;
no warnings 'redefine';

package IRC_Bot::Plugins::Linker;
use HTML::Entities;
use utf8;

sub new { #{{{
	my ($class, $botstate) = @_;
	my $self = {
		urlpart=>qr/(?:[-\._~:\/\?#\[\]\@!\$\&'\(\)\*\+,;=A-Za-z0-9]|%(?:[0-9A-Fa-f]{2}))/,
		curlbinary=> $^O eq 'openbsd' ? '/usr/local/bin/curl' : '/usr/bin/curl'
	};
	bless $self, $class;
	return $self;
} #}}}
sub try_get_title { #{{{
	my ($self, $url) = @_;
	my $fd;
	# check content type!
	open $fd, '-|', $self->{curlbinary}, '-I', '-A', 'Mozilla', '--range', '0-65536', '--max-filesize', '1048576', '-sLm7', $url;
	my $header;
	{
		local $/ = undef;
		$header = <$fd>;
	}
	close $fd;
	if ($header !~ /Content-Type: text\//i) {
		print STDERR "not a text link\n";
		return '';
	}
	open $fd, '-|', $self->{curlbinary}, '-A', 'Mozilla', '--range', '0-65536', '--max-filesize', '1048576', '-sLm7', $url;
	my $page;
	{
		local $/ = undef;
		$page = <$fd>;
	}
	close $fd;
	if ($page =~ /<title>\s*(.*?)\s*<\/title>/s) {
		my $title = $1;
		$title =~ s/\s+/ /gs;
		if ($title ne '') {
			return decode_entities($title);
		}
	}
	else {
		print STDERR "Linker: no title found\n";
	}
	return '';
} #}}}
sub handle_input { #{{{
	my $self = shift;
	my $m = shift;
	my $mynick = shift;
	my @ret = ();
	return () unless $m->{command} eq 'PRIVMSG'; # only extract links from messages
	if (@_) {
		# ( trg who comm params... )
		if (lc $_[2] eq 'help' and lc $_[3] eq 'linker') {
			push @ret, ['PRIVMSG', $_[0], "$_[1]: identifies links (starting with http/https) and fetches their titles"]
		}
	}
	else {
		return () if $m->{params}->[0] eq $mynick; # don't extract links in private messages to the bot
		for my $url ($m->{params}->[1] =~ /https?:\/\/$self->{urlpart}+/g) {
			print "URL MATCH: $url\n";
			my $title = $self->try_get_title($url);
			if ($title ne '' and $title !~ /^(?:imgur|google(?:\.com)?)$/i) {
				push @ret, ['PRIVMSG', $m->{params}->[0], '[ '.$title.' ]'];
			}
		}
	}
	return @ret;
} #}}}

1;

