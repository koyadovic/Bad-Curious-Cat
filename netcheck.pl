#!C:\strawberry\perl\bin\perl.exe

use utf8;

use DBI;
use DBI qw(:sql_types);

use Switch;

use List::Util 'shuffle';
use List::MoreUtils qw(uniq);

use Encode qw(decode encode);

use File::Spec;

#########################################################
# Para toquetear
my $rutadb				= "database.db";

#########################################################

sub get_current_hour {
	($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime();
	return $hour;
}

sub get_timestamp {
	($sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst) = localtime();

	$hour		= sprintf "%02d",	$hour;
	$min		= sprintf "%02d",	$min;
	$sec		= sprintf "%02d",	$sec;

	my $timestamp	= $hour . ":" . $min . ":" . $sec;

	return $timestamp;
}

# Ya que usamos UTF-8, codifica los prints para que en la consola de Windows se vea todo correctamente
sub p {
	my ($text)	= @_;
	my $t		= get_timestamp();
	$text		= encode('cp850', $text);

	print "[$t] $text";
}

sub get_serial_number {
	my ($objetivo)	= @_;
	my $numeroserie	= "";

	for (my $i = 0; $i < 2; $i ++) {
		if(!$numeroserie) {
			$numeroserie	= `wmic /node:$objetivo bios get serialnumber /format:list 2>NUL`;
			$numeroserie	=~ s/SerialNumber=//;
			$numeroserie	=~ s/[\r\n]//g;

			sleep 1 if(!$numeroserie);
		}
	}
	return $numeroserie;
}

sub get_computer_name {
	my $equipo	= "";
	my ($objetivo)	= @_;

	# primer método
	$equipo		= `wmic /node:$objetivo computersystem get name /format:list 2>NUL`;
	$equipo		=~s/[\r,\n,Name=]//g;
	chomp($equipo);

	# método alternativo
	if(!$equipo) {
		sleep 1;
		my @lineas	= `nbtstat -a $objetivo`;
		@lineas		= grep { $_ =~ /\<20\>/; } @lineas;
		($equipo)	= @lineas;
		$equipo		=~ s/\s+([\S]+)\s+<20>.*/\1/;
		chomp($equipo);
	}

	#método alternativo 2
	if(!$equipo) {
		sleep 1;
		my @lineas	= `ping -a -n 1 $objetivo`;
		@lineas		= grep { $_ =~ /\[$objetivo\]/; } @lineas;
		($equipo)	= @lineas;
		$equipo		=~ s/.*\s([\S]+)\s\[$objetivo\].*/\1/;
		chomp($equipo);
	}

	return $equipo;
}

sub get_model {
	my ($objetivo) = @_;

	my $modelo	= `wmic /node:$objetivo computersystem get model /format:list 2>NUL`;
	$modelo		=~ s/Model=//;
	$modelo		=~ s/[\r\n]//g;

	chomp($modelo);
	return $modelo;
}

sub get_operating_system {
	my ($objetivo) = @_;

	my $sistemaoperativo	= `wmic /node:$objetivo os get name /format:list 2>NUL`;
	$sistemaoperativo	=~ s/Name=//;
	$sistemaoperativo	=~ s/[\r\n]//g;
	$sistemaoperativo	=~ s/\|.*//;

	chomp($sistemaoperativo);
	return $sistemaoperativo;
}

sub get_db_user {
	my %result		= ();
	my $all;

	my ($user_to_query)	= @_;
	uc($user_to_query);
	
	$all			= selectall_arrayref("SELECT * FROM users WHERE username = \'$user_to_query\'");

	my $db_user_name, $db_complete_name, $t = 0;

	foreach my $row (@$all) {
		$t 		= 1;
		($db_user_name, $db_complete_name) = @$row;
	}

	$db->disconnect;

	if($t){
		$result{$user_to_query} = $db_complete_name;
	}

	return %result;
}

sub get_ad_complete_name {
	my ($user_to_query) = @_;
	uc($user_to_query);

	$user_to_query =~ s/\s+//g;

	if($user_to_query) {

		for (my $i = 0; $i < 2; $i++){
			my @result = `dsquery user -samid $user_to_query\|dsget user -samid -fn -ln 2>NUL`;

			foreach(@result) {
				if($_ =~ /$user_to_query/i) {

					my $line	= $_;
					$line		=~ s/\s+/ /g;
					$line		=~ s/(^\s*|\s*$)//g;
					$line		=~ s/[\d\w]+\s(.+)/\1/;

					$line = decode('cp850', $line);

					p("get_ad_complete_name:\t\t$user_to_query ->\t$line\n") if ($show_computer_users_found);
					return $line;
				}
			}
			sleep 1;
		}
	}

	return "";
}

# username, complete name (the two parameters needed)
sub add_db_user {
	my ($username, $complete_name) = @_;
	sql_do("INSERT INTO users VALUES (\'$username\', \'$complete_name\')");
	p("add_db_user:\t\t\t$username ->\t$complete_name\n") if ($show_computer_users_found);
}

sub get_computer_users {
	my ($computer) = @_;

	my @users=();

	my $ruta;
	my @rutas = (	"\\\\$computer\\d\$\\Users",
			"\\\\$computer\\c\$\\Users",
			"\\\\$computer\\d\$\\Documents and Settings\\",
			"\\\\$computer\\c\$\\Documents and Settings\\");

	my $max_users = 0;
	my @users_temp=();

	foreach (@rutas){
		chomp;
		if(-d "$_"){
			$ruta		= $_;
			my $tmp		= `dir /OD /B \"$ruta\" 2>NUL`;
			@users_temp	= split('\n', $tmp);

			if($#users_temp + 1 > $max_users) {
				# p("Ruta: En $computer, $ruta tiene más usuarios, seleccionando ésta.\n");
				$max_users = $#users_temp + 1;
				@users = @users_temp;
			}
		}
	}

	foreach(@users){
		chomp;
		$_ = uc;
		$_ =~ s/^\s*([\w\d ]+)\.?.*$/\1/;
		$_ =~ s/(.*)/\"\1\"/ if ($_ =~ / /);
		
	}

	if (($#users_to_ignore + 1) > 0) {
		my $ignore_users	= "(";
		$ignore_users 		.= join('|', @users_to_ignore);
		$ignore_users		.= ")";

		@users = grep { $_ !~ /$ignore_users/i; } @users;
	}

	# @users = grep { $_ !~ /\s+/; } @users;
	@users = grep { $_ ne ""; } @users;
	# @users = grep { $_ !~ /old$/i; } @users;
	@users = uniq @users;

	p("get_computer_users: Encontrado en $ruta: @users\n") if ($show_computer_users_found);
	return @users;
}


# serial, computer name, user, user complete name (four parameters needed)
sub associate_user_to_computer {
	my ($serialnumber, $computer_name, $user, $complete_name) = @_;
	my $all;

	if($serialnumber && $computer_name && $user) {

		$all = sql_selectall_arrayref("SELECT * FROM computers_and_users WHERE serial = \'$serialnumber\' AND computer_name=\'$computer_name\' AND username=\'$user\'");
		my $db_serial, $db_user_name, $t = 0;

		foreach my $row (@$all) {

			$t = 1;

			($db_serial, $db_computer_name, $db_user_name, $db_complete_name) = @$row;

		}

		if(!$t){
			sql_do("INSERT INTO computers_and_users VALUES (\'$serialnumber\', \'$computer_name\', \'$user\', \'$complete_name\')");
			p("associate_user_to_computer:\t$user ->\t$serialnumber\t$computer_name\n") if ($show_computer_users_found);
		}
	}

}

sub get_users_to_ignore {
	my $all = sql_selectall_arrayref("SELECT username FROM users_to_ignore");
	my @users = ();

	my $username;
	foreach my $row (@$all) {
		($username) = @$row;
		uc($username);
		push(@users, $username);
	}

	return @users;
}

sub get_all_networks {
	my $all = sql_selectall_arrayref("SELECT network FROM networks");
	my @networks = ();

	my $network;
	foreach my $row (@$all) {
		($network) = @$row;
		push(@networks, $network);
	}

	return @networks;
}

sub get_alive_ips {
	my ($network) = @_;
	my @resultados = `nmap -sP -n $network 2>NUL`;

	@resultados = grep { $_ =~ /\d+\.\d+\.\d+\.\d+/; } @resultados;

	foreach (@resultados) {
		chomp();
		$_ =~ s/.* (\d+\.\d+\.\d+\.\d+).*/\1/;
		$_ =~ s/(^\s+|\s+$)//g;
	}

	@resultados = shuffle(@resultados);

	p("get_alive_ips:\t\tResultados de la red $network ->\t" . ($#resultados + 1) . " equipos.\n");

	return @resultados;
}

sub sql_do {
	my ($query) = @_;

	my $db = DBI->connect("dbi:SQLite:".$rutadb, "", "", {RaiseError => 1, AutoCommit => 1});
	$db->{sqlite_unicode} = 1;
	my $error = 1;
	while($error) {
		$db->do($query);
		sleep 1 if $db->err;
		$error = $db->err;
	}

	$db->disconnect;
}

sub sql_selectall_arrayref {
	my ($query) = @_;

	my $db = DBI->connect("dbi:SQLite:".$rutadb, "", "", {RaiseError => 1, AutoCommit => 1});
	$db->{sqlite_unicode} = 1;


	my $all;	
	my $error = 1;
	while($error) {
		$all = $db->selectall_arrayref($query);
		sleep 1 if $db->err;
		$error = $db->err;
	}

	$db->disconnect;

	return $all;
}

sub scan {
	# Cogemos el parámetro en el que se especificará la red que husmear.
	my $network 			= shift;
	chomp($network);

	# De la red, nos quedamos con las direcciones IP que responden a ping.
	my @resultados 			= get_alive_ips($network);

	my $hijos			= 0;
	foreach $objetivo (@resultados){

		# Si los procesos hijo han superado el límite esperamos.
		if ($hijos > 4) {
			$pid=wait();
			$hijos--;
		}

		# Hacemos un nuevo proceso hijo
		undef($pid);
		while(! defined($pid)){
			$pid = fork();
			sleep 1 if(! defined($pid));
		}

		# Si el $pid es 0, es que se trata del proceso hijo
		if(!$pid){
			# SERIAL NUMBER
			my $numeroserie = get_serial_number($objetivo);

			if($numeroserie) {
				my $equipo = "", $modelo = "", $sistemaoperativo = "";

				# Hacemos dos intentos			
				for (my $i = 0; $i < 2; $i++){
					# NOMBRE DE EQUIPO
					$equipo			= get_computer_name($objetivo) if (!$equipo);

					# MODELO
					$modelo			= get_model($objetivo) if (!$modelo);

					# OS
					$sistemaoperativo	= get_operating_system($objetivo) if (!$sistemaoperativo);
				}

				if ($equipo){
					$time = localtime();


					my $all = sql_selectall_arrayref("SELECT * FROM computers WHERE serial=\'$numeroserie\' " .
									"AND name=\'$equipo\'");
				
					my $t = 0;
					my $db_serial, $db_name, $db_model, $db_os, $db_last_ip, $db_first_seen, $db_last_seen;
					foreach my $row (@$all) {
						$t = 1;
						($db_serial, $db_name, $db_model, $db_os, $db_last_ip, $db_first_seen, $db_last_seen) = @$row;
					}

					if(!$t){
						# No existe en la DB, hay que añadirlo.
						sql_do(	"INSERT INTO computers VALUES (\'$numeroserie\', \'$equipo\', " .
							"\'$modelo\', \'$sistemaoperativo\', \'$objetivo\', \'$time\', \'$time\')");

						p("scan: Añadimos:\t\t\t$numeroserie\t$equipo\t$objetivo\n");						

					} else {
						# Sí que existe en la DB, hay que actualizarlo.
						my $query = "";

						$query .= "UPDATE computers SET name=\'$equipo\'";
						$query .= ", model=\'$modelo\'" if ($modelo && !$db_model);
						$query .= ", os=\'$sistemaoperativo\'" if ($sistemaoperativo && !$db_os);
						$query .= ", last_ip=\'$objetivo\'";
						$query .= ", last_seen=\'$time\'";
						$query .= " WHERE serial=\'$numeroserie\'";

						sql_do($query);
						p("scan: Actualizamos:\t\t$numeroserie\t$equipo\t$objetivo\n") if ($show_computer_updates);

					}

					# USUARIOS
					my @users = get_computer_users($objetivo);
					foreach (@users){
						if($_) {
							my %user = get_db_user($_);

							if(%user){
								foreach $key (sort(keys %user)) {
									associate_user_to_computer($numeroserie, $equipo, $key, $user{$key});
								}
							} else {
								my $complete_name = get_ad_complete_name($_);
								add_db_user($_, $complete_name);
								associate_user_to_computer($numeroserie, $equipo, $_, $complete_name);
							}
						}
					}
				} else {
					p("scan: Problemas con equipo $objetivo con S/N: $numeroserie. Falta equipo ($equipo) y/o sistema operativo($sistemaoperativo)\n") if($show_computer_name_or_os_errors);
				}
			} else {
				p("scan: Equipo $objetivo no añadido .. No se pudo sacar el número de serie.\n") if ($show_computer_serial_number_errors);
			}

			exit(0);

		} else {

			# Proceso padre
			$hijos++;
			sleep 1;
		}
		
	}
}

sub read_configuration {
	my $all = sql_selectall_arrayref("SELECT * FROM configuration");
				
	foreach my $row (@$all) {

		my ($key, $value) = @$row;

		switch ($key) {
			case "show_computer_updates" { $show_computer_updates = $value; }
			case "show_computer_serial_number_errors" { $show_computer_serial_number_errors = $value ; }
			case "show_computer_name_or_os_errors" { $show_computer_name_or_os_errors = $value; }
			case "show_computer_users_found" { $show_computer_users_found = $value; }
			case "active_hours" { @active_hours = split(',', $value); }
		}
	}

}


sub create_db {

	if (! -e $rutadb){
		my $db = DBI->connect("dbi:SQLite:".$rutadb, "", "", {RaiseError => 1, AutoCommit => 1});
		$db->{sqlite_unicode} = 1;
		$db->do("CREATE TABLE computers (serial TEXT, name TEXT, model TEXT, os TEXT, last_ip TEXT, first_seen TEXT, last_seen TEXT)");
		$db->do("CREATE TABLE users (username TEXT, complete_name TEXT)");
		$db->do("CREATE TABLE computers_and_users (serial TEXT, computer_name TEXT, username TEXT, complete_name TEXT)");
		$db->do("CREATE TABLE networks (network TEXT, location TEXT)");
		$db->do("CREATE TABLE users_to_ignore (username TEXT)");

		$db->do("CREATE TABLE configuration (key TEXT, value TEXT)");
		my $default_config_sql = "";
		$default_config_sql .= "INSERT INTO configuration (key, value) VALUES ";
		$default_config_sql .= "('show_computer_updates', '1'),";
		$default_config_sql .= "('show_computer_serial_number_errors','0'),";
		$default_config_sql .= "('show_computer_name_or_os_errors','1'),";
		$default_config_sql .= "('show_computer_users_found', '1'),";
		$default_config_sql .= "('active_hours', '10,13,17')";

		$db->do($default_config_sql);
		
		$db->disconnect;
		
		p("create_db: Por favor, edite $rutadb para añadir redes en las que escanear, su configuración, etcétera.\n");
		exit(0);
	}
}

sub main {
	# Para crear la base de datos en el caso de que no existiese.
	create_db();
	
	system("mode con:cols=90 lines=4");
	open STDERR, '>', File::Spec->devnull();

	# Inicia desactivado
	my @children_pids = ();
	my $actived = 0;
	p("main: Desactivado.\n");

	while(1){
		read_configuration();
		
		if(!$actived){
			my $h = get_current_hour();
			if( grep ( /$h/, @active_hours )) {
				system("mode con:cols=90 lines=50");
				$actived	= 1;

				print	"main: Activamos el escanner.\n";
				@users_to_ignore = get_users_to_ignore();
				@networks = get_all_networks();
				@networks = shuffle(@networks);

				p("main: Escanearemos las siguientes redes: @networks\n");

				foreach(@networks){
					p("main: Lanzando $_\n");
					my $pid;

					while (! (defined($pid))){
						$pid  = fork();
						sleep 1 if (! (defined ($pid)));
					}

					if(!$pid) {
						scan($_);
						exit(0);

					} else {
						push(@children_pids, $pid);
						sleep(60);
					}

				}

				p("main: No hay más redes para escanear\n");

				sleep 300;
				kill -9, @children_pids;
				@children_pids = ();
			}
		} else {
			my $h = get_current_hour();
			if ( ! (grep ( /$h/, @active_hours))) {
				system("mode con:cols=90 lines=4");
				$actived	= 0;

				print	"main: Desactivamos el escanner.\n";
			}
		}
		sleep 120;
	}
}

# Global variables
my @users_to_ignore;
my $show_computer_updates		= 1;
my $show_computer_serial_number_errors	= 1;
my $show_computer_name_or_os_errors	= 1;
my $show_computer_users_found		= 1;
my @active_hours			= (10, 13, 17);

main();
