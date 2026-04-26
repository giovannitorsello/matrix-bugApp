# =============================================================================
#  Makefile — Matrix (Synapse) + Element  |  Dev Environment
#  Domini: mtr.bug-app.it  /  element.bug-app.it
# =============================================================================
#
#  USO RAPIDO
#  ----------
#  make          → mostra l'help
#  make setup    → genera .env, certs, dynamic_conf e avvia tutto
#  make up       → avvia (richiede setup già eseguito almeno una volta)
#  make down     → ferma i container
#  make logs     → segui i log in tempo reale
#  make clean    → rimuove container, volumi e certificati
#
#  PORTABILITÀ TRA SVILUPPATORI
#  -----------------------------
#  La prima volta: copia .env.example in .env e personalizza UID/GID.
#  Oppure: make setup  (rileva automaticamente l'utente corrente).
#
# =============================================================================

# ---------------------------------------------------------------------------
# 0.  Carica il file .env se esiste (override da riga di comando ha priorità)
# ---------------------------------------------------------------------------
SHELL := /bin/bash
-include .env
export

# ---------------------------------------------------------------------------
# 1.  Identità sviluppatore  (portabile: legge da .env oppure usa l'utente OS)
# ---------------------------------------------------------------------------
DEV_UID  ?= $(shell id -u)
DEV_GID  ?= $(shell id -g)

# ---------------------------------------------------------------------------
# 2.  Domini (personalizza se necessario in .env)
# ---------------------------------------------------------------------------

MATRIX_DOMAIN  := mtr.bug-app.it
ELEMENT_DOMAIN := element.bug-app.it
CA_CN          := BugApp Local Dev CA

# ---------------------------------------------------------------------------
# 3.  Percorsi
# ---------------------------------------------------------------------------
CERTS_DIR  := certs
CA_KEY     := $(CERTS_DIR)/BugApp_dev_ca.key
CA_CERT    := $(CERTS_DIR)/BugApp_dev_ca.crt
SRV_KEY    := $(CERTS_DIR)/BugApp_dev_srv.key
SRV_CERT   := $(CERTS_DIR)/BugApp_dev_srv.crt
SRV_CSR    := $(CERTS_DIR)/BugApp_dev_srv.csr
SAN_EXT    := $(CERTS_DIR)/BugApp_dev_san.ext
DYN_CONF   := dynamic_conf.yaml
ENV_FILE   := .env
ENV_EXAMPLE:= .env.example

COMPOSE    := docker compose
COMPOSE_FILE := ./docker/docker-compose.yaml

# ---------------------------------------------------------------------------
# 4.  Colori terminale
# ---------------------------------------------------------------------------
RESET  := \033[0m
BOLD   := \033[1m
GREEN  := \033[32m
CYAN   := \033[36m
YELLOW := \033[33m
RED    := \033[31m

# ---------------------------------------------------------------------------
# 5.  Target dichiarati come PHONY
# ---------------------------------------------------------------------------
.PHONY: all help setup up down restart logs ps \
        certs ca env dynconf hosts \
        clean clean-certs clean-all

# ---------------------------------------------------------------------------
# 6.  Default
# ---------------------------------------------------------------------------
all: help

# ---------------------------------------------------------------------------
# 7.  Help
# ---------------------------------------------------------------------------
help:
	@printf "\n$(BOLD)  Matrix (Synapse) + Element — Dev Environment$(RESET)\n"
	@printf "  UID=$(DEV_UID)  GID=$(DEV_GID)\n\n"
	@printf "$(CYAN)  Comandi disponibili:$(RESET)\n\n"
	@printf "$(GREEN)  make setup$(RESET)       Prima configurazione completa (env + certs + start)\n"
	@printf "$(GREEN)  make up$(RESET)          Avvia i servizi\n"
	@printf "$(GREEN)  make down$(RESET)        Ferma i container\n"
	@printf "$(GREEN)  make restart$(RESET)     Riavvia tutti i servizi\n"
	@printf "$(GREEN)  make logs$(RESET)        Segui i log in tempo reale\n"
	@printf "$(GREEN)  make ps$(RESET)          Stato dei container\n"
	@printf "$(GREEN)  make certs$(RESET)       (Ri)genera CA locale + certificati TLS\n"
	@printf "$(GREEN)  make hosts$(RESET)       Mostra le righe da aggiungere a /etc/hosts\n"
	@printf "$(GREEN)  make clean$(RESET)       Ferma e rimuove container + volumi\n"
	@printf "$(GREEN)  make clean-certs$(RESET) Rimuove solo i certificati\n"
	@printf "$(GREEN)  make clean-all$(RESET)   Rimuove tutto (container, volumi, certs, .env)\n"
	@printf "\n$(YELLOW)  Dopo 'make certs' importa $(CA_CERT) nel browser come CA attendibile.$(RESET)\n\n"

# ---------------------------------------------------------------------------
# 8.  Setup completo (prima volta o reset)
# ---------------------------------------------------------------------------
setup: env init-dirs certs dynconf
	DEV_UID=$(DEV_UID) DEV_GID=$(DEV_GID) $(COMPOSE) -f $(COMPOSE_FILE) up -d
	@sleep 3
	@$(MAKE) --no-print-directory hosts

# ---------------------------------------------------------------------------
# 9.  Gestione .env
# ---------------------------------------------------------------------------
env: $(ENV_FILE)

$(ENV_FILE):
	@printf "$(CYAN)[env] Creazione $(ENV_FILE)...$(RESET)\n"
	@printf "# Identità sviluppatore — personalizza se necessario\n"   > $(ENV_FILE)
	@printf "DEV_UID=$(DEV_UID)\n"                                     >> $(ENV_FILE)
	@printf "DEV_GID=$(DEV_GID)\n"                                     >> $(ENV_FILE)
	@printf "\n# Domini\n"                                             >> $(ENV_FILE)
	@printf "MATRIX_DOMAIN=$(MATRIX_DOMAIN)\n"                         >> $(ENV_FILE)
	@printf "ELEMENT_DOMAIN=$(ELEMENT_DOMAIN)\n"                       >> $(ENV_FILE)
	@printf "$(GREEN)[env] $(ENV_FILE) creato (UID=$(DEV_UID) GID=$(DEV_GID))$(RESET)\n"

# ---------------------------------------------------------------------------
# 10.  Generazione CA locale
# ---------------------------------------------------------------------------
ca: $(CA_CERT)

$(CA_CERT):
ifeq ($(wildcard ./docker/$(CERTS_DIR)/.),)
	@printf "$(CYAN)[ca]  Generazione CA locale '$(CA_CN)'...$(RESET)\n"
	mkdir -p ./docker/$(CERTS_DIR)
	openssl genrsa -out ./docker/$(CA_KEY) 4096
	openssl req -x509 -new -nodes \
	    -key    ./docker/$(CA_KEY) \
	    -sha256 -days 1825 \
	    -subj   "/CN=$(CA_CN)/O=BugApp Dev/C=IT" \
	    -out    ./docker/$(CA_CERT)
	@printf "$(GREEN)[ca]  CA pronta: ./docker/$(CA_CERT)$(RESET)\n"
	@printf "$(YELLOW)       → Importa ./docker/$(CA_CERT) nel browser come CA attendibile!$(RESET)\n"
else
	@echo "La directory certificati esiste già. Salto generazione CA."
endif

# ---------------------------------------------------------------------------
# 11.  File estensioni SAN (Subject Alternative Names)
# ---------------------------------------------------------------------------
$(SAN_EXT):
ifeq ($(wildcard ./docker/$(CERTS_DIR)/.),)
	@printf "$(CYAN)[certs] Scrittura SAN extensions...$(RESET)\n"
	@printf "subjectAltName        = DNS:$(MATRIX_DOMAIN),DNS:$(ELEMENT_DOMAIN)\n" >  ./docker/$(SAN_EXT)
	@printf "basicConstraints      = CA:FALSE\n"                                   >> ./docker/$(SAN_EXT)
	@printf "keyUsage              = digitalSignature, keyEncipherment\n"          >> ./docker/$(SAN_EXT)
	@printf "extendedKeyUsage      = serverAuth\n"                                 >> ./docker/$(SAN_EXT)
else
	@echo "La directory certificati esiste già. Salto generazone EXT file per i domini"
endif

# ---------------------------------------------------------------------------
# 12.  Certificato server (firmato dalla CA locale)
# ---------------------------------------------------------------------------
certs: $(SRV_CERT)
	@printf "\n$(GREEN)  Certificati pronti in ./docker/$(CERTS_DIR)/$(RESET)\n"
	@printf "$(YELLOW)  Importa ./docker/$(CA_CERT) nel browser come CA attendibile.$(RESET)\n\n"


$(SRV_CERT): $(CA_CERT) $(SAN_EXT)
ifeq ($(wildcard ./docker/$(CERTS_DIR)/.),)
	@printf "$(CYAN)[certs] Generazione chiave e CSR server...$(RESET)\n"
	openssl genrsa -out ./docker/$(SRV_KEY) 4096
	openssl req -new \
	    -key  ./docker/$(SRV_KEY) \
	    -out  ./docker/$(SRV_CSR) \
	    -subj "/CN=$(MATRIX_DOMAIN)/O=BugApp Dev/C=IT"
	@printf "$(CYAN)[certs] Firma del certificato con la CA locale...$(RESET)\n"
	openssl x509 -req \
	    -in         ./docker/$(SRV_CSR) \
	    -CA         ./docker/$(CA_CERT) \
	    -CAkey      ./docker/$(CA_KEY)  \
	    -CAcreateserial \
	    -out        ./docker/$(SRV_CERT) \
	    -days 825   \
	    -sha256     \
	    -extfile    ./docker/$(SAN_EXT)
	@printf "$(GREEN)[certs] ./docker/$(SRV_CERT) generato e firmato.$(RESET)\n"
else
	@echo "La directory certificati esiste già. Salto la generazione dei certificati per traefik."
endif

# ---------------------------------------------------------------------------
# 13.  dynamic_conf.yaml per Traefik (TLS con cert locale)
# ---------------------------------------------------------------------------
dynconf: $(DYN_CONF)

$(DYN_CONF):
	@printf "$(CYAN)[traefik] Generazione ./docker/$(DYN_CONF)...$(RESET)\n"	
	@printf "# Generato da Makefile — non editare a mano\n"                       >  ./docker/$(DYN_CONF)
	@printf "http:\n"                                                             >> ./docker/$(DYN_CONF)
	@printf "  middlewares:\n"                                                    >> ./docker/$(DYN_CONF)
	@printf "    cors-matrix:\n"                                                  >> ./docker/$(DYN_CONF)
	@printf "      headers:\n"                                                    >> ./docker/$(DYN_CONF)
	@printf "        accessControlAllowOriginList:\n"                             >> ./docker/$(DYN_CONF)
	@printf "          - \"https://$(ELEMENT_DOMAIN)\"\n"                         >> ./docker/$(DYN_CONF)
	@printf "        accessControlAllowCredentials: true\n"    					  >> ./docker/$(DYN_CONF)
	@printf "        accessControlAllowHeaders:\n"                                >> ./docker/$(DYN_CONF)
	@printf "          - \"Authorization\"\n"                                     >> ./docker/$(DYN_CONF)
	@printf "          - \"Content-Type\"\n"                                      >> ./docker/$(DYN_CONF)
	@printf "          - \"X-Requested-With\"\n"                                  >> ./docker/$(DYN_CONF)
	@printf "        accessControlAllowMethods:\n"                                >> ./docker/$(DYN_CONF)
	@printf "          - \"GET\"\n"                                               >> ./docker/$(DYN_CONF)
	@printf "          - \"POST\"\n"                                              >> ./docker/$(DYN_CONF)
	@printf "          - \"PUT\"\n"                                               >> ./docker/$(DYN_CONF)
	@printf "          - \"DELETE\"\n"                                            >> ./docker/$(DYN_CONF)
	@printf "          - \"OPTIONS\"\n"                                           >> ./docker/$(DYN_CONF)
	@printf "        accessControlMaxAge: 86400\n"                                >> ./docker/$(DYN_CONF)
	@printf "        addVaryHeader: true\n"   									  >> ./docker/$(DYN_CONF)			
	@printf "# Configurazione TLS dinamica per Traefik\n"                         >> ./docker/$(DYN_CONF)
	@printf "# Generato automaticamente da Makefile — non editare a mano\n"       >> ./docker/$(DYN_CONF)
	@printf "tls:\n"                                                              >> ./docker/$(DYN_CONF)
	@printf "  certificates:\n"                                                   >> ./docker/$(DYN_CONF)
	@printf "    - certFile: $(SRV_CERT)\n"                                       >> ./docker/$(DYN_CONF)
	@printf "      keyFile:  $(SRV_KEY)\n"                                        >> ./docker/$(DYN_CONF)
	@printf "  stores:\n"                                                         >> ./docker/$(DYN_CONF)
	@printf "    default:\n"                                                      >> ./docker/$(DYN_CONF)
	@printf "      defaultCertificate:\n"                                         >> ./docker/$(DYN_CONF)
	@printf "        certFile: $(SRV_CERT)\n"                                     >> ./docker/$(DYN_CONF)
	@printf "        keyFile:  $(SRV_KEY)\n"                                      >> ./docker/$(DYN_CONF)
	@printf "$(GREEN)[traefik] ./docker/$(DYN_CONF) pronto.$(RESET)\n"

# ---------------------------------------------------------------------------
# 14.  Avvio / Arresto / Riavvio
# ---------------------------------------------------------------------------
up: $(SRV_CERT) $(DYN_CONF) init-dirs
	@printf "$(CYAN)[up] Avvio (UID=$(DEV_UID) GID=$(DEV_GID))...$(RESET)\n"
	DEV_UID=$(DEV_UID) DEV_GID=$(DEV_GID) $(COMPOSE) -f $(COMPOSE_FILE) up -d

down:
	@printf "$(CYAN)[down] Arresto servizi...$(RESET)\n"
	$(COMPOSE) -f $(COMPOSE_FILE) down

restart: down up

# ---------------------------------------------------------------------------
# 15.  Utility
# ---------------------------------------------------------------------------
logs:
	$(COMPOSE) -f $(COMPOSE_FILE) logs -f

ps:
	$(COMPOSE) -f $(COMPOSE_FILE) ps

hosts:
	@printf "\n$(YELLOW)  Aggiungi queste righe a /etc/hosts (se non già presenti):$(RESET)\n\n"
	@printf "  127.0.0.1   $(MATRIX_DOMAIN)\n"
	@printf "  127.0.0.1   $(ELEMENT_DOMAIN)\n\n"
	@printf "  Comando rapido (richiede sudo):\n"
	@printf "$(CYAN)    echo '127.0.0.1 $(MATRIX_DOMAIN) $(ELEMENT_DOMAIN)' | sudo tee -a /etc/hosts$(RESET)\n\n"

# ---------------------------------------------------------------------------
# 16.  Pulizia
# ---------------------------------------------------------------------------
clean-certs:
	@printf "$(RED)[clean] Rimozione certificati...$(RESET)\n"
	rm -rf ./docker/$(CERTS_DIR)
	rm -f  ./docker/$(DYN_CONF)

clean-database:
	@printf "$(RED)[clean] Rimozione database e synapse...$(RESET)\n"
	rm -rf ./docker/postgres_data
	rm -rf ./docker/synapse_data	

clean: down
	@printf "$(RED)[clean] Rimozione volumi Docker...$(RESET)\n"
	$(COMPOSE) -f $(COMPOSE_FILE) down -v

clean-all: clean clean-certs clean-database
	@printf "$(RED)[clean-all] Rimozione .env...$(RESET)\n"
	rm -f $(ENV_FILE)
	@printf "$(GREEN)[clean-all] Pulizia completa.$(RESET)\n"

# ---------------------------------------------------------------------------
# 17. inizializzazione directory dati (con permessi corretti per l'utente host)
# ---------------------------------------------------------------------------
init-dirs:
	@printf "$(CYAN)[dirs] Creazione directory dati...$(RESET)\n"
	@mkdir -p ./docker/synapse_data ./docker/postgres_data ./docker/element
	@printf "$(CYAN)[dirs] Applicazione permessi $(DEV_UID):$(DEV_GID)...$(RESET)\n"
	@if ! chown -R $(DEV_UID):$(DEV_GID) \
	        ./docker/synapse_data \
	        ./docker/postgres_data \
	        ./docker/element 2>/dev/null; then \
	    printf "$(YELLOW)[dirs] chown richiede sudo...$(RESET)\n"; \
	    sudo chown -R $(DEV_UID):$(DEV_GID) \
	        ./docker/synapse_data \
	        ./docker/postgres_data \
	        ./docker/element; \
	fi
	@chmod 700 ./docker/synapse_data ./docker/postgres_data
	@printf "$(GREEN)[dirs] OK → synapse_data, postgres_data, element = $(DEV_UID):$(DEV_GID)$(RESET)\n"
	@ls -la ./docker/ | grep -E 'synapse_data|postgres_data|element'
		
# ---------------------------------------------------------------------------
# 18. create-admin: registra l'utente admin Matrix (richiede Synapse in esecuzione)
# ---------------------------------------------------------------------------
create-admin:
	@printf "$(CYAN)[matrix] Creazione nuovo utente Matrix (non-admin)...$(RESET)\n"
	printf "Username: "; read MATRIX_USER; \
	printf "Password: "; read -s MATRIX_PASSWORD; printf "\n"; \
	SHARED_SECRET=$$(grep 'registration_shared_secret' ./docker/synapse_data/homeserver.yaml \
	    | awk '{print $$2}' | tr -d "'\""); \
	docker exec synapse register_new_matrix_user \
	    --user     "$$MATRIX_USER" \
	    --password "$$MATRIX_PASSWORD" \
	    --admin \
	    --shared-secret "$$SHARED_SECRET" \
	    http://localhost:8008 \
	&& printf "$(GREEN)[matrix] Utente @$$MATRIX_USER:$(MATRIX_DOMAIN) creato.$(RESET)\n" \
	|| printf "$(RED)[matrix] Errore nella creazione utente.$(RESET)\n"
# ---------------------------------------------------------------------------
# 19. create-user: registra un utente non-admin interattivo
# ---------------------------------------------------------------------------
create-user:
	@printf "$(CYAN)[matrix] Creazione nuovo utente Matrix (non-admin)...$(RESET)\n"
	printf "Username: "; read MATRIX_USER; \
	printf "Password: "; read -s MATRIX_PASSWORD; printf "\n"; \
	SHARED_SECRET=$$(grep 'registration_shared_secret' ./docker/synapse_data/homeserver.yaml \
	    | awk '{print $$2}' | tr -d "'\""); \
	docker exec synapse register_new_matrix_user \
	    --user     "$$MATRIX_USER" \
	    --password "$$MATRIX_PASSWORD" \
	    --no-admin \
	    --shared-secret "$$SHARED_SECRET" \
	    http://localhost:8008 \
	&& printf "$(GREEN)[matrix] Utente @$$MATRIX_USER:$(MATRIX_DOMAIN) creato.$(RESET)\n" \
	|| printf "$(RED)[matrix] Errore nella creazione utente.$(RESET)\n"

delete-user:
	@printf "$(CYAN)[matrix] Eliminazione utente Matrix...$(RESET)\n"
	@printf "Username da eliminare: "; read MATRIX_USER; \
	FULL_ID="@$$MATRIX_USER:$(MATRIX_DOMAIN)"; \
	printf "$(YELLOW)[matrix] Eliminazione $$FULL_ID dal database...$(RESET)\n"; \
	docker exec synapse_db psql -U synapse synapse -c "DELETE FROM access_tokens      WHERE user_id = '$$FULL_ID';" \
	                                                -c "DELETE FROM refresh_tokens     WHERE user_id = '$$FULL_ID';" \
	                                                -c "DELETE FROM devices             WHERE user_id = '$$FULL_ID';" \
	                                                -c "DELETE FROM user_ips            WHERE user_id = '$$FULL_ID';" \
	                                                -c "DELETE FROM pushers             WHERE user_id = '$$FULL_ID';" \
	                                                -c "DELETE FROM user_threepids      WHERE user_id = '$$FULL_ID';" \
	                                                -c "DELETE FROM profiles            WHERE user_id = '$$MATRIX_USER';" \
	                                                -c "DELETE FROM user_filters        WHERE user_id = '$$FULL_ID';" \
	                                                -c "DELETE FROM user_directory      WHERE user_id = '$$FULL_ID';" \
	                                                -c "DELETE FROM users               WHERE name    = '$$FULL_ID';" \
	&& printf "$(GREEN)[matrix] $$FULL_ID eliminato completamente.$(RESET)\n" \
	|| printf "$(RED)[matrix] Errore nella eliminazione.$(RESET)\n"

delete-admin:
	@printf "$(CYAN)[matrix] Eliminazione utente admin '$(MATRIX_ADMIN_USER)'...$(RESET)\n"
	@FULL_ID="@$(MATRIX_ADMIN_USER):$(MATRIX_DOMAIN)"; \
	docker exec synapse_db psql -U synapse synapse -c "DELETE FROM access_tokens      WHERE user_id = '$$FULL_ID';" \
	                                                -c "DELETE FROM refresh_tokens     WHERE user_id = '$$FULL_ID';" \
	                                                -c "DELETE FROM devices             WHERE user_id = '$$FULL_ID';" \
	                                                -c "DELETE FROM user_ips            WHERE user_id = '$$FULL_ID';" \
	                                                -c "DELETE FROM pushers             WHERE user_id = '$$FULL_ID';" \
	                                                -c "DELETE FROM user_threepids      WHERE user_id = '$$FULL_ID';" \
	                                                -c "DELETE FROM profiles            WHERE user_id = '$(MATRIX_ADMIN_USER)';" \
	                                                -c "DELETE FROM user_filters        WHERE user_id = '$$FULL_ID';" \
	                                                -c "DELETE FROM user_directory      WHERE user_id = '$$FULL_ID';" \
	                                                -c "DELETE FROM users               WHERE name    = '$$FULL_ID';" \
	&& printf "$(GREEN)[matrix] $$FULL_ID eliminato completamente.$(RESET)\n" \
	|| printf "$(RED)[matrix] Errore nella eliminazione.$(RESET)\n"

# ---------------------------------------------------------------------------
# 20.  Inizializzazione homeserver.yaml (solo se non esiste)
# ---------------------------------------------------------------------------
build-synapse:
	@printf "$(CYAN)[synapse] Build immagine con UID=$(DEV_UID) GID=$(DEV_GID)...$(RESET)\n"
	DEV_UID=$(DEV_UID) DEV_GID=$(DEV_GID) \
	    $(COMPOSE) -f $(COMPOSE_FILE) build synapse
	@printf "$(GREEN)[synapse] Build completata.$(RESET)\n"
	
init-synapse:
	@if [ -f ./docker/synapse_data/homeserver.yaml ]; then \
	    printf "$(YELLOW)[synapse] homeserver.yaml già presente — skip.\n"; \
	    printf "          Usa 'make clean-all' per ripartire da zero.$(RESET)\n"; \
	else \
	    printf "$(CYAN)[synapse] Generazione homeserver.yaml...$(RESET)\n"; \
	    mkdir -p ./docker/synapse_data; \
	    chown $(DEV_UID):$(DEV_GID) ./docker/synapse_data; \
	    docker run --rm \
	        --user "$(DEV_UID):$(DEV_GID)" \
	        -v "$$(pwd)/docker/synapse_data:/data" \
	        -e SYNAPSE_SERVER_NAME=$(MATRIX_DOMAIN) \
	        -e SYNAPSE_REPORT_STATS=no \
	        matrixdotorg/synapse:latest generate; \
	    printf "$(YELLOW)\n  Modifica obbligatoria in docker/synapse_data/homeserver.yaml:\n"; \
	    printf "    public_baseurl: \"https://$(MATRIX_DOMAIN)\"\n"; \
	    printf "    x_forwarded: true  (nel blocco listeners)\n"; \
	    printf "    registration_shared_secret: \"una-stringa-segreta\"\n\n$(RESET)"; \
	    printf "$(CYAN)[synapse] Premi INVIO per riavviare synapse e continuare$(RESET)\n"; \
	    read DUMMY; \
	    printf "$(CYAN)[synapse] Riavvio synapse...$(RESET)\n"; \
	    docker compose -f $(COMPOSE_FILE) restart synapse; \
	    printf "$(GREEN)[synapse] Synapse riavviato.$(RESET)\n"; \
	fi