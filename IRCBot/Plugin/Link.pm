use warnings;
use strictures 2;
package IRCBot::Plugin::Link;
use parent 'IRCBot::Plugin::PluginBase';
use IRCBot::Event;
use IRCBot::Message;
use LWP::UserAgent;
use HTML::HeadParser;
use Data::Dumper;

sub new { #{{{
	my $class = shift;

	my $self = IRCBot::Plugin::PluginBase->new(@_);
	my $browser = LWP::UserAgent->new;
	$browser->agent('Mozilla/5.0');
	@{$self}{qw/version browser/} = ('0.2.4', $browser);
	bless $self, $class;

	return $self;

} #}}}
sub fetch_url_title { #{{{
	my $self = shift;
	my $url = shift;
	my $p = HTML::HeadParser->new;
	my $r = $self->{browser}->head($url, Accept=>'text/*, application/xhtml+xml');
	if ($r->content_type =~ m,(?:text/.*)|(?:application/xhtml\+xml),) {
		$r = $self->{browser}->get(
			$url,
			Accept=>'text/*,application/xhtml+xml',
			Range=>'bytes=0-65535');
		$p->parse($r->content);
		my $title = $p->header('Title');
		if (!defined $title) {
			$r->content =~ m,<title>([^<]*)</title>,;
			$title = $1//'';
			$title =~ s/\s+/ /sg;
		}
		return $title;
	}
	else {
		$self->log_d("content-type: ".$r->content_type);
		return '';
	}
} #}}}
sub mk_youtube_string { #{{{
	my $self = shift;
	my $ytid = shift;
	my $url = "https://youtu.be/$ytid";
	my $title = $self->fetch_url_title($url);
	return "[ $url | $title ]" if $title ne '' && $title ne 'YouTube';
	$self->log_d("empty title or wrong content-type from $url");
	return '';
} #}}}
sub mk_url_string { #{{{
	my $self = shift;
	my $url = shift;
	my $title = $self->fetch_url_title($url);
	return "[ $title ]" if $title ne '';
	$self->log_d("empty title or wrong content-type from $url");
	return '';
} #}}}
sub handle_event { #{{{
	my $self = shift;
	my $e = shift;
	if ($e->target eq 'link' && $e->type eq 'ACL-RESPONSE') {
		if ($e->{acl_data}->{trust} >= $self->{config}->{min_trustlevel}) {
			$self->handle_designators(%{$e->{data}});
		}
	}
} #}}}
sub try_extract_url {
	my $self = shift;
	my $mdata = shift;
	my @ret = ();
	@ret = map { ['url', $_] } $mdata =~ m|\b(https?://[^\x00-\x20]+)\b|g;
	return @ret;
}
sub try_extract_youtube {
	my $self = shift;
	my $mdata = shift;
	my @ret = ();
	@ret = map { ['yt', $1] } $mdata =~ m|\byt:([^\x00-\x20]+)\b|g;
	return @ret;
}
sub handle_designators { #{{{
	my $self = shift;
	my %h = @_;
	my $response_channel = $h{channel};
	my @designators = @{$h{designators}};
	for (@designators) {
		my $t = '';
		if ($_->[0] eq 'url') {
			$t = $self->mk_url_string($_->[1]);
		}
		elsif ($_->[0] eq 'yt') {
			$t = $self->mk_youtube_string($_->[1]);
		}
		if ($t ne '') {
			$self->emit_message(
				command=>'PRIVMSG',
				params=>[$response_channel, "$t / $h{who}"]);
		}
	}
} #}}}
sub handle_message { #{{{
	my $self = shift;
	my $m = shift;

	if ($m->c eq 'PRIVMSG') {
		if ($m->p0 ne $self->identity->{nick}) {
			# never annotate links in private chat
			my @designators = ();
			push @designators, $self->try_extract_url($m->p1);
			push @designators, $self->try_extract_youtube($m->p1);
			for (@designators) {
				$self->log_d("designator match: type: '$_->[0]', value: '$_->[1]'");
			}
			if (exists $self->config->{use_acl} && $self->config->{use_acl} eq 'NO') {
				# acl disabled
				$self->handle_designators(who=>$m->{name}, channel=>$m->p0, designators=>\@designators);
			}
			else {
				# acl enabled: only link for people above a certain level of trust
				$self->emit_event(
					target=>'acl', origin=>'link',
					type=>'ACL-QUERY', nick=>$m->{name},
					data=>{channel=>$m->p0, designators=>\@designators, who=>$m->{name}});
			}
		}
	}
} #}}}
1;

