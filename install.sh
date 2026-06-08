#!/bin/bash

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Конфигурация
GITHUB_REPO="https://github.com/smirdch183/amneziabot.git"
PROJECT_DIR="/opt/amnezia-bot"
CONTAINER_NAME="amneziabot"
IMAGE_NAME="amneziabot"
ENV_FILE=".env"
USERS_FILE="users.json"
PORT="8080"
SCRIPT_PATH="/usr/local/bin/amneziabot"
VERSION_FILE="$PROJECT_DIR/.version"

# Функции вывода
print_message() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Запускайте с правами root (sudo)"
        exit 1
    fi
}

install_docker() {
    if ! command -v docker &> /dev/null; then
        print_message "Установка Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
        systemctl enable docker
        systemctl start docker
    fi
}

# Проверка новой версии
check_update() {
    print_message "Проверка обновлений..."
    
    cd "$PROJECT_DIR"
    git fetch origin 2>/dev/null
    
    LOCAL=$(git rev-parse HEAD 2>/dev/null)
    REMOTE=$(git rev-parse @{u} 2>/dev/null)
    
    if [ -z "$LOCAL" ] || [ -z "$REMOTE" ]; then
        print_error "Не удалось проверить обновления"
        return 1
    fi
    
    if [ "$LOCAL" = "$REMOTE" ]; then
        print_message "✅ У вас последняя версия"
        return 0
    else
        # Показываем что изменилось
        echo ""
        print_warning "Доступна новая версия!"
        echo ""
        git log --oneline HEAD..@{u} 2>/dev/null | head -5
        echo ""
        return 2
    fi
}

create_command() {
    print_message "Создание команды amneziabot..."
    
    cat > "$SCRIPT_PATH" << 'SCRIPTEOF'
#!/bin/bash

PROJECT_DIR="/opt/amnezia-bot"
CONTAINER_NAME="amneziabot"
IMAGE_NAME="amneziabot"
ENV_FILE=".env"
USERS_FILE="users.json"
PORT="8080"
BACKUP_DIR="/opt/backups"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_message() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Запускайте с правами root (sudo)"
        exit 1
    fi
}

check_env() {
    TOKEN=$(grep "^TOKEN=" "$PROJECT_DIR/$ENV_FILE" | cut -d'=' -f2)
    ADMIN_ID=$(grep "^ADMIN_ID=" "$PROJECT_DIR/$ENV_FILE" | cut -d'=' -f2)
    
    if [ -z "$TOKEN" ]; then
        print_error "TOKEN не указан в .env файле!"
        return 1
    fi
    
    if [ -z "$ADMIN_ID" ]; then
        print_error "ADMIN_ID не указан в .env файле!"
        return 1
    fi
    
    return 0
}

fix_users_file() {
    USERS_PATH="$PROJECT_DIR/$USERS_FILE"
    
    if [ -d "$USERS_PATH" ]; then
        rm -rf "$USERS_PATH"
    fi
    
    if [ ! -f "$USERS_PATH" ]; then
        echo "{}" > "$USERS_PATH"
    fi
    
    chmod 644 "$USERS_PATH"
}

deploy_bot() {
    if ! check_env; then
        print_error "Настройте .env файл: sudo amneziabot env"
        exit 1
    fi
    
    fix_users_file
    
    print_message "Остановка старого контейнера..."
    docker stop "$CONTAINER_NAME" 2>/dev/null
    docker rm "$CONTAINER_NAME" 2>/dev/null

    print_message "Сборка образа..."
    cd "$PROJECT_DIR"
    docker build -t "$IMAGE_NAME:latest" .

    print_message "Запуск контейнера..."
    docker run -d \
        --env-file "$PROJECT_DIR/$ENV_FILE" \
        -p "$PORT:$PORT" \
        -v "$PROJECT_DIR/$USERS_FILE:/app/$USERS_FILE" \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        "$IMAGE_NAME:latest"
    
    if [ $? -eq 0 ]; then
        print_message "✅ Бот запущен!"
        sleep 2
        docker logs --tail 5 "$CONTAINER_NAME"
    else
        print_error "❌ Ошибка запуска!"
    fi
}

# Проверка обновлений
check_version() {
    cd "$PROJECT_DIR"
    git fetch origin 2>/dev/null
    
    LOCAL=$(git rev-parse HEAD 2>/dev/null)
    REMOTE=$(git rev-parse @{u} 2>/dev/null)
    
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║        Проверка обновлений            ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    if [ -z "$LOCAL" ] || [ -z "$REMOTE" ]; then
        print_error "Не удалось проверить обновления"
        return
    fi
    
    echo "Текущая версия: ${LOCAL:0:7}"
    echo "Последняя версия: ${REMOTE:0:7}"
    echo ""
    
    if [ "$LOCAL" = "$REMOTE" ]; then
        print_message "✅ У вас последняя версия"
    else
        print_warning "Доступна новая версия!"
        echo ""
        echo "Изменения:"
        git log --oneline HEAD..@{u} | head -10
        echo ""
        print_info "Для обновления: sudo amneziabot update"
    fi
}

# Полное удаление
full_uninstall() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║      ⚠️  Удаление AmneziaBot          ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    print_warning "ВНИМАНИЕ! Это удалит ВСЁ:"
    echo "  - Контейнер Docker"
    echo "  - Образ Docker"
    echo "  - Все файлы бота в $PROJECT_DIR"
    echo "  - Команду amneziabot"
    echo ""
    echo "Данные которые МОЖНО сохранить:"
    echo "  - $PROJECT_DIR/$USERS_FILE (пользователи)"
    echo "  - $PROJECT_DIR/$ENV_FILE (настройки)"
    echo ""
    
    read -p "Сохранить бэкап перед удалением? (y/n): " BACKUP_CHOICE
    if [ "$BACKUP_CHOICE" = "y" ]; then
        mkdir -p "$BACKUP_DIR"
        BACKUP_FILE="$BACKUP_DIR/backup_before_uninstall_$(date +%Y%m%d_%H%M%S).tar.gz"
        cd "$PROJECT_DIR"
        tar -czf "$BACKUP_FILE" "$USERS_FILE" "$ENV_FILE" 2>/dev/null
        print_message "Бэкап сохранен: $BACKUP_FILE"
    fi
    
    echo ""
    read -p "Вы уверены? Введите YES для подтверждения: " CONFIRM
    
    if [ "$CONFIRM" != "YES" ]; then
        print_message "Удаление отменено"
        exit 0
    fi
    
    print_message "Остановка контейнера..."
    docker stop "$CONTAINER_NAME" 2>/dev/null
    
    print_message "Удаление контейнера..."
    docker rm "$CONTAINER_NAME" 2>/dev/null
    
    print_message "Удаление образа..."
    docker rmi "$IMAGE_NAME:latest" 2>/dev/null
    
    print_message "Удаление файлов бота..."
    rm -rf "$PROJECT_DIR"
    
    print_message "Удаление команды amneziabot..."
    rm -f /usr/local/bin/amneziabot
    
    echo ""
    print_message "✅ AmneziaBot полностью удален!"
    echo ""
    echo "Если вы сохранили бэкап, он находится в: $BACKUP_DIR"
    echo ""
}

case "$1" in
    start)
        check_root
        if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
            docker start "$CONTAINER_NAME"
            print_message "✅ Бот запущен!"
        else
            deploy_bot
        fi
        ;;
    
    update)
        check_root
        
        # Проверяем есть ли обновления
        cd "$PROJECT_DIR"
        git fetch origin
        LOCAL=$(git rev-parse HEAD)
        REMOTE=$(git rev-parse @{u})
        
        if [ "$LOCAL" = "$REMOTE" ]; then
            print_message "У вас уже последняя версия"
            exit 0
        fi
        
        print_message "Обновление..."
        git pull origin main
        deploy_bot
        print_message "✅ Бот обновлен!"
        ;;
    
    check)
        check_version
        ;;
    
    restart)
        check_root
        docker restart "$CONTAINER_NAME"
        print_message "✅ Бот перезапущен!"
        ;;
    
    stop)
        check_root
        docker stop "$CONTAINER_NAME"
        print_message "Бот остановлен"
        ;;
    
    logs)
        docker logs -f "$CONTAINER_NAME"
        ;;
    
    status)
        docker ps --filter "name=$CONTAINER_NAME"
        ;;
    
    env)
        nano "$PROJECT_DIR/$ENV_FILE"
        ;;
    
    uninstall)
        check_root
        full_uninstall
        ;;
    
    backup)
        check_root
        mkdir -p "$BACKUP_DIR"
        BACKUP_FILE="$BACKUP_DIR/backup_$(date +%Y%m%d_%H%M%S).tar.gz"
        cd "$PROJECT_DIR"
        tar -czf "$BACKUP_FILE" "$USERS_FILE" "$ENV_FILE"
        print_message "✅ Бэкап создан: $BACKUP_FILE"
        ;;
    
    *)
        echo ""
        echo "╔════════════════════════════════════════╗"
        echo "║        AmneziaBot - Управление        ║"
        echo "╚════════════════════════════════════════╝"
        echo ""
        echo "Использование: amneziabot [команда]"
        echo ""
        echo "Основные:"
        echo "  start      - Запустить бота"
        echo "  stop       - Остановить бота"
        echo "  restart    - Перезапустить бота"
        echo "  status     - Статус бота"
        echo "  logs       - Просмотр логов"
        echo ""
        echo "Обновление:"
        echo "  check      - Проверить новую версию"
        echo "  update     - Обновить из GitHub"
        echo ""
        echo "Настройки:"
        echo "  env        - Редактировать .env"
        echo "  backup     - Создать бэкап"
        echo ""
        echo "Удаление:"
        echo "  uninstall  - Полностью удалить бота"
        echo ""
        ;;
esac
SCRIPTEOF

    chmod +x "$SCRIPT_PATH"
    print_message "✅ Команда amneziabot создана!"
}

clone_repo() {
    print_message "Клонирование репозитория..."
    
    if [ -d "$PROJECT_DIR" ]; then
        rm -rf "$PROJECT_DIR"
    fi
    
    git clone "$GITHUB_REPO" "$PROJECT_DIR"
    cd "$PROJECT_DIR"
}

create_env_file() {
    cat > "$PROJECT_DIR/$ENV_FILE" << 'EOF'
TOKEN=
ADMIN_ID=
GUI=False
ADMIN_LOGIN=admin
ADMIN_PASS=change-me
WEB_HOST=localhost
WEB_PORT=8080
EOF
    chmod 644 "$PROJECT_DIR/$ENV_FILE"
}

create_users_file() {
    USERS_PATH="$PROJECT_DIR/$USERS_FILE"
    
    if [ -d "$USERS_PATH" ]; then
        rm -rf "$USERS_PATH"
    fi
    
    echo '{}' > "$USERS_PATH"
    chmod 644 "$USERS_PATH"
    
    print_message "✅ users.json создан"
}

main() {
    check_root
    
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║     Установка AmneziaBot              ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    
    install_docker
    clone_repo
    create_env_file
    create_users_file
    create_command
    
    echo ""
    echo "=========================================="
    print_message "✅ Установка завершена!"
    echo "=========================================="
    echo ""
    print_warning "1. Измените TOKEN и ADMIN_ID:"
    echo ""
    print_info "   sudo amneziabot env"
    echo ""
    print_warning "2. Запустите бота:"
    echo ""
    print_info "   sudo amneziabot start"
    echo ""
    echo "=========================================="
    echo ""
    echo "Другие команды:"
    echo "  sudo amneziabot check      - Проверить обновления"
    echo "  sudo amneziabot update     - Обновить бота"
    echo "  sudo amneziabot uninstall  - Полностью удалить"
    echo ""
}

main