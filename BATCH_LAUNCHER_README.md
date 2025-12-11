# ATX CLI Batch Launcher

A comprehensive batch processing script for running ATX CLI transformations on multiple repositories with support for both serial and parallel execution modes.

## Quick Start

Get up and running in 3 simple steps:

### 1. Install ATX CLI
Follow the installation instructions in the [official ATX CLI documentation](https://docs.aws.amazon.com/transform/latest/userguide/custom.html):
```bash
curl -fsSL https://desktop-release.transform.us-east-1.api.aws/install.sh | bash
```

### 2. Configure Your Repository List
Edit the sample CSV file with your repositories and transformations:
```bash
# Edit sample-repos.csv with your repositories
nano sample-repos.csv
# or
vim sample-repos.csv
```

### 3. Configure Authentication for Private Repositories (Optional)

For private GitHub repositories, you have two options:

#### Option 1: SSH Keys (Recommended - Easier)

**Advantages:**
- ✅ Set up once, works forever
- ✅ No tokens to manage/expire  
- ✅ More secure (no credentials in files)
- ✅ No prompts during git clone operations
- ✅ No script modifications needed

**Setup:**
```bash
# 1. Generate SSH key WITHOUT passphrase (press Enter when prompted)
ssh-keygen -t ed25519 -C "your_email@example.com"

# 2. Add to ssh-agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# 3. Copy public key to GitHub
cat ~/.ssh/id_ed25519.pub
# Go to GitHub → Settings → SSH and GPG keys → New SSH key
# Paste the public key content

# 4. Test SSH connection
ssh -T git@github.com
# Should show: "Hi username! You've successfully authenticated..."
```

**Usage:** Use SSH URLs in your CSV file:
```csv
git@github.com:user/private-repo.git
```

#### Option 2: Personal Access Token (More Complex)

**Setup:**
1. Go to GitHub → Settings → Developer settings → Personal access tokens
2. Generate new token with `repo` permissions
3. Configure git credentials or use HTTPS URLs with embedded tokens

**Note:** SSH is recommended as it's simpler and more secure.

### 4. Run the Batch Launcher
```bash
# Basic execution using sample files
./sample-execution.sh

# Or run directly
./atx-batch-launcher.sh --csv-file sample-repos.csv

# Parallel execution with custom settings
./atx-batch-launcher.sh \
  --csv-file "sample-repos.csv" \
  --mode "parallel" \
  --max-jobs 10 \
  --output-dir "./batch_results" \
  --clone-dir "./batch_repos"
```

That's it! Check `batch_results/summary.log` for execution results.

## Sample Files

### sample-execution.sh

This script demonstrates common usage patterns and serves as a template for your own execution scripts:

```bash
#!/bin/bash

./atx-batch-launcher.sh \
  --csv-file "sample-repos.csv" \
  --mode "parallel" \
  --max-jobs 8 \
  --output-dir "./batch_results" \
  --clone-dir "./batch_repos"
```

**Key Features Demonstrated:**
- **Parallel execution** with 8 concurrent jobs
- **Sample CSV file** with realistic repository examples
- **Standard output directories** for results and cloned repos

**Usage Examples:**
```bash
# Run the sample script directly
./sample-execution.sh

# Copy and customize for your needs
cp sample-execution.sh my-java-upgrades.sh
# Edit my-java-upgrades.sh with your parameters
./my-java-upgrades.sh

# Create custom execution scripts
cat > my-custom-execution.sh << 'EOF'
#!/bin/bash
./atx-batch-launcher.sh \
  --csv-file "sample-repos.csv" \
  --mode "serial" \
  --max-jobs 4 \
  --build-command "mvn clean install" \
  --output-dir "./results-$(date +%Y%m%d)"
EOF
chmod +x my-custom-execution.sh
```

**Customization Options:**
- Change `--csv-file` to your repository list
- Adjust `--max-jobs` based on system resources
- Modify `--mode` (serial/parallel) for your workflow
- Set custom `--output-dir` and `--clone-dir` paths
- Add `--build-command` for default build instructions

### sample-repos.csv

This file demonstrates the CSV format with realistic examples:

```csv
repo_path,build_command,transformation_name,validation_commands,additional_plan_context
https://github.com/spring-projects/spring-petclinic.git,./mvnw clean test,java-version-upgrade,"Use JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64/bin/java and run all tests","Java 8 to 21 transformation with Spring Boot 3.4.5 and dependency migrations"
https://github.com/eugenp/tutorials.git,./gradlew clean build test,aws-sdk-migration,"Build with Java 21 and validate AWS SDK v2 usage","Migrate from AWS SDK v1 to v2 with proper error handling"
./local-spring-app,mvn clean install,spring-boot-upgrade,"Run integration tests with TestContainers","Spring Boot 2.7 to 3.4 migration with security updates"
https://github.com/Netflix/eureka.git,./gradlew build,modernization-package,"Use Java 21 and run all unit tests","Modernize to latest Spring Cloud and remove deprecated APIs"
```

**Repository Types Demonstrated:**
- **Public GitHub repos** (Spring PetClinic, Baeldung Tutorials, Netflix Eureka)
- **Local repositories** (./local-spring-app)
- **Different build systems** (Maven, Gradle)
- **Various transformations** (Java upgrades, AWS SDK migration, Spring Boot upgrades)

**For Private Repositories:** Use SSH URLs like `git@github.com:user/private-repo.git` after setting up SSH keys.

## Features

- **CSV-based input** - Define repositories and parameters in a simple CSV format
- **Flexible repository sources** - Support for local paths, GitHub HTTPS URLs, and SSH URLs
- **Execution modes** - Serial or parallel processing with configurable job limits
- **Comprehensive logging** - Individual logs per repository plus summary statistics
- **Error handling** - Retry mechanisms, timeout handling, and graceful cleanup
- **Trust management** - Trust-all-tools enabled by default for automation
- **Progress tracking** - Real-time status updates and completion statistics
- **Resume capability** - Retry failed repositories from previous runs
- **Production ready** - File locking, signal handling, disk space validation
- **ATX version management** - Automatic version checking and update notifications

## Installation

1. Make the script executable:
```bash
chmod +x atx-batch-launcher.sh
```

2. Ensure ATX CLI is installed and accessible in your PATH

## Usage

### Basic Usage

```bash
# Basic serial execution (trust-all-tools enabled by default, non-interactive by default)
./atx-batch-launcher.sh --csv-file repos.csv --build-command "mvn clean install"

# Parallel execution with 8 jobs
./atx-batch-launcher.sh --csv-file repos.csv --mode parallel --max-jobs 8

# Disable trust-all-tools for manual approval
./atx-batch-launcher.sh --csv-file repos.csv --no-trust-tools

# Dry run to see what would be executed
./atx-batch-launcher.sh --csv-file repos.csv --dry-run
```

### Command Line Options

| Option | Description | Default |
|--------|-------------|---------|
| `--csv-file <file>` | CSV file containing repository information | Required |
| `--mode <serial\|parallel>` | Execution mode | `serial` |
| `--no-trust-tools` | Disable trust-all-tools (default: enabled) | `false` |
| `--max-jobs <number>` | Max parallel jobs (must be positive integer) | `4` |
| `--max-retries <number>` | Max retry attempts per repo (must be non-negative integer) | `1` |
| `--output-dir <dir>` | Output directory for logs | `./batch_results` |
| `--clone-dir <dir>` | Directory for cloning GitHub repos | `./batch_repos` |
| `--build-command <cmd>` | Default build command | None |
| `--additional-params <params>` | Additional ATX CLI parameters | `--non-interactive` |
| `--dry-run` | Show what would be executed without running | `false` |
| `--retry-failed` | Retry previously failed repositories | `false` |
| `--help` | Show help message | - |

### CSV Format

The CSV file should have the following columns:

```csv
repo_path,build_command,transformation_name,validation_commands,additional_plan_context
```

**Column Descriptions:**
- `repo_path`: Local path or GitHub URL (HTTPS/SSH)
- `build_command`: Build command (optional, uses default if empty)
- `transformation_name`: Transformation to use (required)
- `validation_commands`: Validation commands for this transformation (optional)
- `additional_plan_context`: Additional context for transformation planning (optional)

**Note:** Repository names are automatically generated from the path (directory name for local paths, repository name for URLs).

### Additional Parameters

You can use `--additional-params` to pass any ATX CLI parameters. Common options include:

**Execution Control:**
- `--non-interactive` - Run without user interaction (default)
- `--trust-all-tools` - Trust all tools without prompting (enabled by default)
- `--configuration <config>` - Use configuration file (e.g., `file://config.yaml`)

**Knowledge Management:**
- `--do-not-use-knowledge-items` - Disable knowledge items from previous transformations
- `--do-not-learn` - Prevent extracting knowledge items from execution

**Conversation Management:**
- `--conversation-id <id>` - Resume specific conversation
- `--resume` - Resume most recent conversation

**Examples of additional parameters:**
```bash
# Disable learning and knowledge items
--additional-params "--non-interactive --do-not-learn --do-not-use-knowledge-items"

# Resume specific conversation
--additional-params "--conversation-id abc123def456"
```

### Per-Repository Configuration

Each repository can have its own validation commands and additional plan context specified directly in the CSV file. This allows for transformation-specific customization:

**Validation Commands**: Commands or instructions for validating the transformation success
**Additional Plan Context**: Extra context to help the transformation agent understand the specific requirements

**Examples:**
```csv
# Java transformations with specific JDK requirements
repo_path,build_command,transformation_name,validation_commands,additional_plan_context
./java8-app,mvn clean test,java-version-upgrade,"Use JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64/bin/java","Java 8 to 21 transformation with Spring Boot 3.4.5"

# Python transformations with version requirements  
./python-app,pytest,python-upgrade,"Run tests with Python 3.11","Django 3.2 to 4.2 migration with async support"

# Node.js transformations
./node-app,npm test,node-upgrade,"Use Node.js 20 LTS","Express 4 to 5 migration with TypeScript"
```

**Benefits of per-repository configuration:**
- Different transformations can have different validation requirements
- Specific context can be provided for each codebase
- More flexible than global parameters
- Better suited for mixed-technology batch processing

### Example CSV

```csv
repo_path,build_command,transformation_name,validation_commands,additional_plan_context
./local-java-app,mvn clean install,aws-sdk-v1-to-v2-java-migration,"Use JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64/bin/java","Java 8 to 21 transformation with Spring Boot 3.4.5"
https://github.com/example/spring-boot-app.git,./gradlew build,spring-boot-upgrade,"Run all tests with Java 21","Migrate to Spring Boot 3.4.5 and AWS SDK 2.31.40"
/home/user/projects/legacy-app,npm run build,modernization-package,"","Node.js 16 to 20 migration"
git@github.com:company/microservice.git,make build,java-version-upgrade,"Use JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64/bin/java","Include all dependency migrations"
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ATX_SHELL_TIMEOUT` | Shell command timeout in seconds | `10800` (3 hours) |

**Note:** The script automatically checks for ATX CLI updates at startup and displays notifications if newer versions are available.

## Output Structure

The script creates the following output structure:

```
batch_results/
├── summary.log                    # Complete execution summary with statistics
├── <repo_name>_execution.log      # Individual repository logs
├── <repo_name>_config.yaml        # Generated config files (if validation/context provided)
├── results.txt                    # Machine-readable results
├── failed_repos.csv              # CSV of failed repositories (if any)
└── parsed_repos.txt              # Internal parsed repository data

batch_repos/                       # Cloned GitHub repositories
├── <repo_name>/                   # Auto-generated from repository URLs
└── ...
```

## Summary Report

The summary report includes:

- **Statistics Table**: Total repositories, success/failure counts, success rate
- **Execution Details**: Wall time, execution time, mode, parameters
- **Failed Repositories**: List of failed repos with error messages
- **Detailed Results**: Complete status table for all repositories
- **Log File Locations**: Paths to all generated logs

Example summary output:
```
STATISTICS TABLE
==================
Metric               | Value     
---------------------+----------
Total Repositories   | 6         
Successful           | 4         
Failed               | 2         
Success Rate         | 66%       
Execution Mode       | parallel  
Trust All Tools      | true      
```

## Example Execution Scripts

Several example scripts are provided:

**Basic Execution:**
```bash
# Simple execution with default parameters
./execute-batch.sh
```

**Documentation Analysis:**
```bash
# Run comprehensive codebase analysis with 8 parallel jobs
./run-doc-analysis.sh

# Dry run with additional parameters
./run-doc-analysis-dryrun.sh
```

These scripts demonstrate:
- Basic serial and parallel execution
- Custom output and clone directories
- Dry run mode with validation commands
- Additional plan context usage

## Advanced Usage

### Retry Failed Repositories

After a batch execution, you can retry only the failed repositories:

```bash
./atx-batch-launcher.sh --retry-failed --output-dir ./previous_batch_results
```

### Custom Configuration

Use environment variables for advanced configuration:

```bash
# Set 5-hour timeout
export ATX_SHELL_TIMEOUT=18000

# Run with custom parameters
./atx-batch-launcher.sh \
  --csv-file repos.csv \
  --mode parallel \
  --max-jobs 6 \
  --trust-all-tools \
  --transformation-name "my-custom-transformation" \
  --additional-params "--non-interactive --do-not-learn"
```

### Parallel Execution Best Practices

- **CPU-bound transformations**: Set max-jobs to number of CPU cores
- **I/O-bound transformations**: Can use 2-4x CPU cores
- **Memory considerations**: Monitor memory usage with high job counts
- **Network limitations**: Consider bandwidth when cloning multiple repos

## Error Handling

The script includes comprehensive error handling:

- **Repository preparation failures**: Logged and skipped
- **ATX CLI execution failures**: Retried once with detailed logging
- **Timeout handling**: Uses system timeout command if available
- **Signal handling**: Graceful cleanup on SIGINT/SIGTERM
- **Parallel job management**: Proper cleanup of background processes

## Troubleshooting

### Common Issues

1. **ATX CLI not found**
   - Ensure ATX CLI is installed and in PATH
   - Check with `which atx` or `atx --version`

2. **Permission denied on repositories**
   - Ensure proper SSH keys for Git repositories
   - Check file permissions for local paths

3. **Timeout issues**
   - Increase `ATX_SHELL_TIMEOUT` environment variable
   - Check individual repository logs for specific issues

4. **Memory issues with parallel execution**
   - Reduce `--max-jobs` parameter
   - Monitor system resources during execution

### Log Analysis

- **summary.log**: Overall execution status and statistics
- **<repo>_execution.log**: Detailed ATX CLI output for each repository
- **results.txt**: Machine-readable results for scripting

## Production Readiness

The batch launcher is production-ready with the following features:

### **Reliability**
- Comprehensive error handling and configurable retry mechanisms (via `--max-retries`)
- Signal handling for graceful cleanup (SIGINT/SIGTERM)
- Timeout protection with configurable limits
- Automatic cleanup of failed clones and temporary files
- File locking for concurrent writes in parallel mode (prevents race conditions)
- Early validation of ATX CLI availability and version checking before processing
- Disk space validation (requires minimum 1GB free space)

### **Monitoring & Logging**
- Detailed logging per repository with timestamps
- Comprehensive summary reports with statistics tables
- Machine-readable results for automation integration
- Progress tracking for long-running operations
- Automatic generation of failed repositories CSV for retry capability

### **Resource Management**
- Configurable parallel job limits to prevent resource exhaustion
- Input validation for all numeric parameters (prevents invalid configurations)
- Automatic cleanup of cloned repositories between runs
- Memory-efficient CSV parsing for large repository lists
- Proper process management for parallel execution

### **Security**
- Trust-all-tools enabled by default for automation but configurable via `--no-trust-tools`
- No hardcoded credentials or sensitive data
- Secure temporary file handling
- Git clone error handling to prevent malicious repositories

### **Scalability**
- Supports unlimited repositories via CSV input
- Parallel execution with configurable job limits
- Efficient workspace management for large codebases
- Resume capability for interrupted executions
- Atomic file operations for safe concurrent processing

## Integration

The batch launcher can be integrated into CI/CD pipelines:

```bash
# Example CI/CD usage
./atx-batch-launcher.sh \
  --csv-file $WORKSPACE/repos.csv \
  --mode parallel \
  --max-jobs 4 \
  --trust-all-tools \
  --output-dir $WORKSPACE/atx-results

# Check exit code
if [ $? -eq 0 ]; then
  echo "Batch transformation completed successfully"
else
  echo "Batch transformation failed"
  exit 1
fi
```

## License

This script is provided under the same license as the ATX CLI.
