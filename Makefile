################
# General Jobs #
################

default: deploy

hdc: hdc-prep deploy upgrade-reboot


###################
# Individual jobs #
###################

# Check prerequisites, pull/build and deploy containers, then test ssh keys
deploy: env config-docker config-mongodb
	@	[ $(MODE) != "dev" ]||[ -s ./docker/dev.yml ] || \
			sudo cp ./docker/dev.yml-sample ./docker/dev.yml
	@	. ./config.env; \
		sudo TAG=$(TAG) VOLS_CONFIG=$${VOLS_CONFIG} VOLS_DATA=$${VOLS_DATA} docker-compose $(YML) pull; \
		sudo TAG=$(TAG) VOLS_CONFIG=$${VOLS_CONFIG} VOLS_DATA=$${VOLS_DATA} docker-compose $(YML) build; \
		sudo TAG=$(TAG) VOLS_CONFIG=$${VOLS_CONFIG} VOLS_DATA=$${VOLS_DATA} docker-compose $(YML) up -d
	@	sudo docker exec gateway /ssh_test.sh


# Import SQL and export E2E to Gateway containers
import:
	@	sudo docker pull hdcbc/e2e_oscar:"${TAG}"
	@	. ./config.env; \
		RECORDS_BEFORE=$$( sudo docker exec gateway_db mongo query_gateway_development --eval 'db.records.count();' | grep -v -e "MongoDB" -e "connecting" ); \
		TIME_BEFORE=$$( date +%s ); \
		SQL_PATH=$${DIR:-"$${VOLS_DATA}/import/"}; \
		SQL_PATH=$$( realpath $${SQL_PATH} ); \
		sudo docker run --rm --name e2e-oscar -h e2e-oscar --link gateway --volume "$${SQL_PATH}":/import:rw hdcbc/e2e_oscar:"${TAG}"; \
		TIME_AFTER=$$( date +%s ); \
		TIME_TOTAL=$$( expr "$${TIME_AFTER}" - "$${TIME_BEFORE}" ); \
		RECORDS_AFTER=$$( sudo docker exec gateway_db mongo query_gateway_development --eval 'db.records.count();' | grep -v -e "MongoDB" -e "connecting" ); \
		echo; \
		echo "Records"; \
		echo "  Before:  $${RECORDS_BEFORE}"; \
		echo "  After:   $${RECORDS_AFTER}"; \
		echo; \
		echo "Export time"; \
		echo "  Seconds: $${TIME_TOTAL}"; \
		echo


# Auto-import (cron, incron) packages - TODO: switch to apt (not apt-get) when Ubuntu 14.04 is dropped
auto-import-packages:
	@	( which cron && which incrond )|| \
			( sudo apt-get update && sudo apt-get install cron incron -y)
	@	sudo grep -q $$( whoami ) /etc/incron.allow || \
			echo $$( whoami ) | sudo tee -a /etc/incron.allow


# Additional setup for HDC managed solutions
hdc-prep: hdc-ssh config-docker
	@	$(MAKE) -C hdc


# Create HDC ssh key at beginning of setup, for convenience
hdc-ssh: env
	$(MAKE) ssh -C hdc


# Configures and sources environment, used as a prerequisite; clip trailing /s
env:
	@	if ! [ -s ./config.env ]; \
		then \
		        cp ./config.env-sample ./config.env; \
		        vim config.env; \
		fi
	@	sed -i "s|/$$||" config.env


# Docker and Docker Compose installs
config-docker:
	@	which docker-compose || wget -qO- https://raw.githubusercontent.com/HDCbc/devops/master/deploy/docker_setup.sh | sh


# Disable Transparent Hugepage, for MongoDb
config-mongodb:
	@	( echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled )> /dev/null
	@	( echo never | sudo tee /sys/kernel/mm/transparent_hugepage/defrag )> /dev/null
	@	if(! grep --quiet 'never > /sys/kernel/mm/transparent_hugepage/enabled' /etc/rc.local ); \
		then \
			sudo sed -i '/exit 0/d' /etc/rc.local; \
			( \
				echo ''; \
				echo '# Disable Transparent Hugepage, for Mongo'; \
				echo '#'; \
				echo 'echo never > /sys/kernel/mm/transparent_hugepage/enabled'; \
				echo 'echo never > /sys/kernel/mm/transparent_hugepage/defrag'; \
				echo ''; \
				echo 'exit 0'; \
			) | sudo tee -a /etc/rc.local; \
		fi; \
		sudo chmod 755 /etc/rc.local


# Apply final settings and reboot
upgrade-reboot:
	@	sudo apt-get update
	@	sudo apt-get upgrade -y
	@	sudo apt-get dist-upgrade -y
	@	sudo update-grub
	@	sudo reboot now


# Import Sample10 data into a Gateway
sample-data:
	@	sudo docker exec gateway /gateway/util/sample10/import.sh || true


################
# Runtime prep #
################


# Default tag (e.g. latest, dev, 0.1.2) and build mode (e.g. prod, dev)
#
TAG  ?= latest
MODE ?= prod


# Default is docker-compose.yml, add dev.yml for development
#
YML ?= -f ./docker/deploy.yml
ifeq ($(MODE),dev)
	YML += -f ./docker/dev.yml
endif
