use warnings;
use strictures 2;
package IRCBot::Plugin::UserData;
use parent 'IRCBot::Plugin::PluginBase';
use IRCBot::Event;
use IRCBot::Message;
use HTML::Entities;

sub new { #{{{
	my $class = shift;

	my $self = IRCBot::Plugin::PluginBase->new(@_);
	@{$self}{qw/version/} = ('0.0.0-alpha-24');
	bless $self, $class;

	return $self;

} #}}}
sub get_dir_for { #{{{
	my $self = shift;
	my $who = shift;
	my $hex = sprintf '%*v02X', '', $who;
	my $dir = $self->config->{base_path}.'/'.$hex;
	return $dir;
} #}}}
sub get_url_for { #{{{
	my $self = shift;
	my $who = shift;
	my $hex = sprintf '%*v02X', '', $who;
	my $url = $self->config->{base_url}.'/'.$hex.'/list.html';
	return $url;
} #}}}
sub try_fetch_links_for {
	my $self = shift;
	my $who = shift;
	my $dir = $self->get_dir_for($who);
	if (not -d $dir) {
		return;
	}
	open my $fh, '<', $dir.'/list.html' or return;
	my @links = ();
	for (<$fh>) {
		if (m,^<span class="index">\d+</span> <a href="([^"]+)">\[link\]</a> <span class="description">([^<]+)</span><br>$,) {
			$self->log_d("got a line: $_");
			my $url = $1//'';
			my $description = decode_entities($2//'no description');
			$url = 'https://'.$url unless $url =~ m,^[a-zA-Z0-9]+://,;
			push @links, {description=>$description, url=>$url};
		}
	}
	close $fh;
	return @links;
}
sub try_write_links_for {
	my $self = shift;
	my $who = shift;
	my @links = @_;
	my $dir = $self->get_dir_for($who);
	my $fn = $dir.'/list.html';
	if (@links == 0) {
		unlink $fn if -f $fn;
		rmdir $dir if -d $dir;
		return 1;
	}
	if (not -d $dir) {
		mkdir $dir, 0755;
	}
	open my $fh, '>', $fn or return undef;
	printf $fh <<'BOILERPLATE0'
<!DOCTYPE HTML>
<html><body>
<h1>Link list for <span class="nick">%s</span></h1><br>

BOILERPLATE0
, encode_entities($who);
	if (@links) {
		my $index = -1;
		for my $index (0..$#links) {
			my $link = $links[$index];
			my $url = $link->{url}//'example.org';
			my $description = encode_entities($link->{description}//'example description');
			printf $fh '<span class="index">%d</span> <a href="%s">[link]</a> <span class="description">%s</span><br>'."\n",
				$index, $url, $description;
		}
	}
	else {
		print $fh, "This link list is empty.<br>\n";
	}
	print $fh <<'BOILERPLATE1'
</body></html>
BOILERPLATE1
;
	close $fh;
	chmod 0644, $fn;
	return 1;
}
sub try_display_links {
	my $self = shift;
	my $where = shift;
	my $prefix = shift;
	my $who = shift;
	my @links = @_;
	if (@links) {
		my $lb = 0;
		if (4 < @links) {
			my $resturl = $self->get_url_for($who);
			$self->emit_message(
				command=>'PRIVMSG',
				params=>[$where, $prefix."latest links stored by $who: (rest at $resturl)"]);
			$lb = $#links-3;
		}
		else {
			$self->emit_message(
				command=>'PRIVMSG',
				params=>[$where, $prefix."links stored by $who:"]);
		}
		for my $index ($lb..$#links) {
			my $link = $links[$index];
			$self->emit_message(
				command=>'PRIVMSG',
				params=>[$where, $prefix.$index.') '.$link->{description}.' :: '.$link->{url}]);
		}
	}
	else {
		$self->emit_message(
			command=>'PRIVMSG',
			params=>[$where, $prefix.'empty list']);
	}
}
sub handle_event { #{{{
	my $self = shift;
	my $e = shift;
	$self->log_d($e->deflate);
	if ($e->type eq 'ACL-RESPONSE') {
		$self->log_d('directed acl response');
		if (defined $e->{acl_data}) {
			my $p = $e->{data}->{parsed};
			if ($e->{acl_data}->{trust} >= 1) {
				my $comm = $e->{data}->{comm};
				my $rest = $e->{data}->{rest};
				my @linksin = $self->try_fetch_links_for($e->{nick});
				my @linksout = ();
				if ($comm eq 'list+') {
					$self->log_d('list plus: ');
					@linksout = @linksin;
					$rest =~ /^(.*?)\s+(\S+)$/;
					push @linksout, {description=>$1, url=>$2};
				}
				elsif ($comm eq 'list-') {
					my @ixes = split /\s+/, $rest;
					$self->log_d('list minus');
					for my $i (0..$#linksin) {
						# ineffective but simple
						push @linksout, $linksin[$i] unless 0 < grep {$i == $_} @ixes;
						if (0 < grep {$i == $_} @ixes) {
							$self->log_d("removing index $i ".$linksin[$i]->{url});
						}
						else {
							$self->log_d("not removing index $i ".$linksin[$i]->{url});
						}
					}
				}
				if ($self->try_write_links_for($e->{nick}, @linksout)) {
					$self->emit_message(
						command=>'PRIVMSG',
						params=>[$p->{respond_target}, $p->{respond_prefix}."Link list has been modified."]);
				}
			}
			else {
				$self->emit_message(
					command=>'PRIVMSG',
					params=>[$p->{respond_target}, $p->{respond_prefix}."Access denied."]);
			}
		}
	}
} #}}}
sub handle_message { #{{{
	my $self = shift;
	my $m = shift;
	if ($m->c eq 'PRIVMSG') {
		my $p = $self->decode_privmsg($m);
		if ($p->{addressed} > 0) {
			my ($comm, $rest) = split /\s+/, $p->{message}, 2;
			$self->log_d("got a <$comm> message with rest <".($rest//'').">");
			if ($comm eq 'list+' || $comm eq 'list-') {
				$self->log_d("got a plusminus message");
				$self->emit_event(target=>'acl', origin=>'user_data', type=>'ACL-QUERY', nick=>$m->{name}, data=>{parsed=>$p, comm=>$comm, rest=>$rest});
			}
			elsif ($comm eq 'list') {
				my $who = $rest;
				if (defined $rest && $rest ne '') {
					$who = $rest;
				}
				else {
					$who = $m->{name};
				}
				my @links = $self->try_fetch_links_for($who);
				$self->try_display_links($p->{respond_target}, $p->{respond_prefix}, $who, @links);
			}
		}
	}
} #}}}
1;

