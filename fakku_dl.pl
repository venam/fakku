#!/bin/perl
use warnings;
use strict;

use Net::Curl::Easy qw(:constants);
use Getopt::Long;
#use Cwd;

#Nice Colours
my $HEADER      = "\033[95m";
my $OKBLUE      = "\033[94m";
my $OKGREEN     = "\033[92m";
my $WARNING     = "\033[93m";
my $FAIL        = "\033[91m";
my $ENDC        = "\033[0m";
my $INFO        = $HEADER . "[". $OKBLUE ."*" . $HEADER ."] ". $ENDC;
my $ARROW       = " ". $OKGREEN . ">> ". $ENDC;
my $PLUS        = $HEADER ."[" . $OKGREEN ."+" . $HEADER ."] ". $ENDC;
my $MINUS       = $HEADER ."[". $FAIL ."-". $HEADER ."] ". $ENDC;

#the curl handle
my $easy  =  Net::Curl::Easy->new({ body => '' });

#takes a page as argument & returns the source
sub get_page_source($) {
	my ($page) = @_;
	print "$INFO Getting source of $page\n";
#	$easy  =  Net::Curl::Easy->new({ body => '' });
#	empty the body instead of recreating a new handle everytime
	$easy->{body} = "";
	$easy->setopt( CURLOPT_URL, $page );
	$easy->setopt( Net::Curl::Easy::CURLOPT_FILE(),\$easy->{body} );
	$easy->perform();
	return $easy->{body};
}

#takes the source & array of links as arguments -> fills in the array with 
#the manga list inside the source
sub get_inside_links($$) {
	my ($source,$links) =  @_;
	print "$INFO Getting inside links\n";
	my @spliter  = split /<a href/, $source;
	for my $k (@spliter) {
		if ($k =~ /class="sample"/) {
			$k =~ s/="//;
			$k  = (split /">/, $k)[0];
			push @$links, $k;
		}
	}
}

#takes 2 arguments
#1: the keyword
#2: the way the search is done (artists, series, or search)
sub get_all_list($$) {
	my ($name,$what) = @_;
	print "$INFO Getting everything related to $name by $what\n";
	$name =~ s/ /%20/gg;
	my $source = get_page_source("http://www.fakku.net/".$what."/".$name);
	my $nb_pages = 0;
	#if has multiple pages save the number of pages
	if ($source =~ /Page <b>1<\/b> of <b>(\d+)<\/b>/) {
		$nb_pages = $1;
	}
	my @links;
	get_inside_links($source, \@links);
	#now checks if there are more pages
	if ($nb_pages != 0) {
		for (2..$nb_pages) {
			print "$INFO Searching next page\n";
			my $source = get_page_source("http://www.fakku.net/".$what."/".$name."/page/".$_);
			get_inside_links($source, \@links);
		}
	}
	return @links;
}

#take one of the element of the get_all_list() and returns all the available imgs
sub get_all_imgs($) {
	my ($name) = @_;
	print "$INFO Getting all images\n";
	my @source = split /\n/, get_page_source("http://www.fakku.net".$name."/read#page=1");
	my @imgs;
	my $line;
	for (@source) {
		if ( /window.params.thumbs = \["https:/) {
			$_ =~ s/window.params\.thumbs = \["//;
			$_ =~ s/\"];//;
			@imgs = split /","/, $_;
			for my $i (@imgs) {
				$i =~ s/thumbs/images/;
				$i =~ s/\.thumb//;
				$i =~ s/\\//gg;
			}
			last;
		}
	}
	return @imgs;

}

#takes a command and a filename
#it will execute the command
#returns -1 if it fails, 0 otherwise
sub execute_command($$) {
	my ($command, $tmp) = @_;

	system($command);
	if ($? == -1) {
		print "$MINUS Failed to execute: $!\n";
		return -1;
	}
	elsif ($? & 127) {
		printf "$MINUS Child died with signal %d, %s coredump\n",
			($? & 127),  ($? & 128) ? 'with' : 'without';
		return -1;
	}
	print "$PLUS Finished downloading image $tmp\n";
	return 0;
}

#take the mg name, a list of imgs, an external dl manager, & a location
#it will download all the imgs from the array using the dl manager
#replacing IMG with the image url and OUT with the image output
sub download_each_imgs($$$$$) {
	my ($mg_name, $imgs, $extrn_dl_mngr, $location, $encrypt)  = @_;
	if (substr ($location, length($location-1), length($location-1)) eq "/") {
		$location = substr($location, 0, length($location-2));
	}
	#dir with the manga name exist or not
	unless (-d $mg_name)  {
		mkdir $mg_name;
	}
	#loop through imgs and download them all
	for (@$imgs) {
		my $command = $extrn_dl_mngr;
		$command =~ s/IMG/$_/;
		my $tmp = reverse ((split /\//, reverse $_)[0]);
		$tmp    = $mg_name."/".$tmp;
		$command =~ s/OUT/$tmp/;
		print $command."\n";
		my $stat = -1;
		while ($stat !=0) {
			$stat = execute_command($command, $tmp);
		}
		if ($encrypt) {
			print "$INFO Encrypting using password in file $encrypt\n";
			system( "ccrypt -e --keyfile ".$encrypt." ".$tmp);
		}
	}
}

#take a location as input
#checks if it exists, move to it
#returns 1 if exists, 0 if not
sub manage_location($) {
	my ($location) = @_;
	if (-d -w $location) {
		chdir $location;
		return 1;
	}
	else {
		print "$MINUS $location isn't a dir or you might not have the permission to access it\n";
		return 0;
	}
}

sub usage() {
	return qq#
	$0 [--list|--download] [Options]
	--list                  list all the results
	--search "keywords"     general search using keywords
	--artists "keywords"    search by artists using keywords
	--series "keywords"     search by series using keywords
	--location "directory"  the directory where the files will be downloaded (default \$HOME)
	--dl_mngr               download manager used to download the files 
	                       (default axel -aS "IMG" -o "OUT", replace OUT and IMG by the output 
							   and image url respectively)
	--encrypt "secretfile"  encrypt using the password in the file specified (absolute location)
	\n#;
}

#Default Values
my $is_download   = 0;
my $is_list       = 0;
my $search        = "";
my $artists       = "";
my $series        = "";
my $location      = $ENV{"HOME"};
my $dl_mngr       = q#axel -aS "IMG" -o OUT#;
my $encrypt       = "";
my $help          = 0;

GetOptions (
	"help"       => \$help,         #flag
	"list"       => \$is_list,      #flag
	"download"   => \$is_download,  #flag
	"search=s"   => \$search,       #string
	"artists=s"  => \$artists,      #string
	"series=s"   => \$series,       #string
	"location=s" => \$location,     #string
	"dl_mngr=s"  => \$dl_mngr,      #string
	"encrypt=s"  => \$encrypt,      #flag
)  or die("$MINUS Error in command line arguments\n");

#defensive programming
if ($help) {
	print usage();
	exit;
}
if (!$search && !$artists && !$series) {
	print "$MINUS You must specify how the search should be done\n";
	print usage();
	exit;
}
if ($is_download && $is_list) {
	print "$MINUS Cannot download and list at the same time\n";
	print usage();
	exit;
}
if ($encrypt) {
	if (! -r $encrypt) {
		print "$MINUS Cannot read from file $encrypt\n";
		exit;
	}
#	else {
#		$encrypt = getcwd()."/".$encrypt ;
#	}
}

my $search_way = "";
my $keywords   = "";
if ($search) {
	$search_way = "search";
	$keywords = $search;
}
elsif ($artists) {
	$search_way = "artists";
	$keywords   = $artists;
}
elsif ($series) {
	$search_way = "series";
	$keywords   = $series;
}
if (manage_location($location)) {
	my @links = get_all_list($keywords ,$search_way);

	if ($is_list) {
		for (@links) {
			print "http://www.fakku.net".$_."\n";
		}
	}
	elsif ($is_download) {
		for my $link (@links) {
			my @imgs = get_all_imgs($link);
			my $mg_name = reverse ((split /\//, reverse $link)[0] );
			download_each_imgs($mg_name,\@imgs, $dl_mngr, $location, $encrypt);
		}
	}
}

