# Nextcloud-Install

This repository contains a bash script to automate the installation of Nextcloud on Debian or Ubuntu servers. The script handles the installation and configuration of necessary dependencies, web server setup, database setup, and Nextcloud installation.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Usage](#usage)
- [Features](#features)
- [Logs](#logs)
- [Contributing](#contributing)
- [License](#license)

## Prerequisites

Before running the script, ensure you have the following:

- A Debian or Ubuntu server
- Superuser (root) privileges

## Usage

1. Clone the repository:

   ```bash
   git clone https://github.com/yourusername/Nextcloud-Install.git
   cd Nextcloud-Install
   ```

2. Make the script executable:

   ```bash
   chmod +x nextcloud_install.sh
   ```

3. Run the script with superuser privileges:

   ```bash
   sudo ./nextcloud_install.sh
   ```

4. Follow the prompts to select your distribution and web server.

## Features

- **Automatic Dependency Installation:** Installs PHP 8.2, required PHP extensions, MariaDB, Redis, and more.
- **Web Server Configuration:** Supports both Apache and Nginx.
- **Database Configuration:** Creates a database and user for Nextcloud with randomly generated credentials.
- **Nextcloud Configuration:** Sets up Nextcloud with optimal settings for performance and security.
- **Logging:** Captures the output of each command to a log file for troubleshooting.

## Logs

The script creates a log file at `/var/log/nextcloud_install.log` to record the output of each command executed. This log can be used to troubleshoot any issues that arise during the installation.

## Contributing

Contributions are welcome! Please fork the repository and submit a pull request.

1. Fork the repository
2. Create a feature branch (`git checkout -b feature-branch`)
3. Commit your changes (`git commit -am 'Add new feature'`)
4. Push to the branch (`git push origin feature-branch`)
5. Open a pull request

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

---

By following the steps outlined in this README, you should be able to successfully install and configure Nextcloud on your server. If you encounter any issues, refer to the log file or open an issue in the repository. Happy self-hosting!
