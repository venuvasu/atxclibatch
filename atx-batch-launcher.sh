#!/bin/bash

# ATX CLI Batch Launcher Script
# Executes ATX CLI transformations on multiple repositories from CSV input

set -euo pipefail

# Default configuration
DEFAULT_SHELL_TIMEOUT=10800  # 3 hours in seconds
DEFAULT_MAX_PARALLEL_JOBS=4
DEFAULT_OUTPUT_DIR="./batch_results"
DEFAULT_CLONE_DIR="./batch_repos"
DEFAULT_MAX_RETRIES=1

# Global variables
CSV_FILE=""
EXECUTION_MODE="serial"
TRUST_ALL_TOOLS=true
MAX_PARALLEL_JOBS=$DEFAULT_MAX_PARALLEL_JOBS
OUTPUT_DIR=$DEFAULT_OUTPUT_DIR
CLONE_DIR=$DEFAULT_CLONE_DIR
DRY_RUN=false
BUILD_COMMAND=""
ADDITIONAL_PARAMS="--non-interactive"
RETRY_FAILED=false
MAX_RETRIES=$DEFAULT_MAX_RETRIES

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# File locking for concurrent writes
write_with_lock() {
    local file="$1"
    local content="$2"
    local lockfile="${file}.lock"
    local max_wait=30
    local waited=0
    
    # Wait for lock with timeout
    while ! mkdir "$lockfile" 2>/dev/null; do
        sleep 0.1
        waited=$((waited + 1))
        if [[ $waited -gt $((max_wait * 10)) ]]; then
            echo "Warning: Lock timeout for $file" >&2
            return 1
        fi
    done
    
    # Write content
    echo "$content" >> "$file"
    
    # Release lock
    rmdir "$lockfile"
    return 0
}

# Usage function
usage() {
    cat << EOF
ATX CLI Batch Launcher Script

USAGE:
    $0 [OPTIONS] --csv-file <file>

REQUIRED:
    --csv-file <file>           CSV file containing repository information

OPTIONS:
    --mode <serial|parallel>    Execution mode (default: serial)
    --no-trust-tools           Disable trust-all-tools (default: enabled)
    --max-jobs <number>        Max parallel jobs (default: $DEFAULT_MAX_PARALLEL_JOBS)
    --max-retries <number>     Max retry attempts per repo (default: $DEFAULT_MAX_RETRIES)
    --output-dir <dir>         Output directory for logs (default: $DEFAULT_OUTPUT_DIR)
    --clone-dir <dir>          Directory for cloning GitHub repos (default: $DEFAULT_CLONE_DIR)
    --build-command <cmd>      Default build command (can be overridden in CSV)
    --additional-params <params> Additional ATX CLI parameters (default: --non-interactive)
    --dry-run                  Show what would be executed without running
    --retry-failed             Retry previously failed repositories
    --help                     Show this help message

ENVIRONMENT VARIABLES:
    ATX_SHELL_TIMEOUT          Shell command timeout (default: $DEFAULT_SHELL_TIMEOUT seconds / 3 hours)

CSV FORMAT:
    repo_path,build_command,transformation_name,validation_commands,additional_plan_context
    
    - repo_path: Local path or GitHub URL
    - build_command: Build command (optional, uses default if empty)
    - transformation_name: Transformation to use (required)
    - validation_commands: Validation commands for this transformation (optional)
    - additional_plan_context: Additional context for transformation planning (optional)

ADDITIONAL PARAMETERS:
    Common ATX CLI parameters you can use with --additional-params:
    --non-interactive          Run without user interaction (default)
    --do-not-use-knowledge-items  Disable knowledge items from previous transformations
    --do-not-learn             Prevent extracting knowledge items from execution
    --configuration <config>   Use configuration file (file://config.yaml)
    --conversation-id <id>     Resume specific conversation
    --resume                   Resume most recent conversation

EXAMPLES:
    # Basic serial execution (trust-all-tools enabled by default)
    $0 --csv-file repos.csv --build-command "mvn clean install"
    
    # Parallel execution with custom parameters
    $0 --csv-file repos.csv --mode parallel --max-jobs 8 --additional-params "--non-interactive --do-not-learn"
    
    # Disable trust-all-tools
    $0 --csv-file repos.csv --no-trust-tools
    
    # Dry run to see what would be executed
    $0 --csv-file repos.csv --dry-run

EOF
}

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$OUTPUT_DIR/summary.log"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$OUTPUT_DIR/summary.log"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$OUTPUT_DIR/summary.log"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$OUTPUT_DIR/summary.log"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --csv-file)
                CSV_FILE="$2"
                shift 2
                ;;
            --mode)
                EXECUTION_MODE="$2"
                if [[ "$EXECUTION_MODE" != "serial" && "$EXECUTION_MODE" != "parallel" ]]; then
                    echo "Error: Mode must be 'serial' or 'parallel'"
                    exit 1
                fi
                shift 2
                ;;
            --no-trust-tools)
                TRUST_ALL_TOOLS=false
                shift
                ;;
            --max-jobs)
                if ! [[ "$2" =~ ^[1-9][0-9]*$ ]]; then
                    echo "Error: --max-jobs must be a positive integer"
                    exit 1
                fi
                MAX_PARALLEL_JOBS="$2"
                shift 2
                ;;
            --max-retries)
                if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    echo "Error: --max-retries must be a non-negative integer"
                    exit 1
                fi
                MAX_RETRIES="$2"
                shift 2
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --clone-dir)
                CLONE_DIR="$2"
                shift 2
                ;;
            --build-command)
                BUILD_COMMAND="$2"
                shift 2
                ;;
            --additional-params)
                ADDITIONAL_PARAMS="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --retry-failed)
                RETRY_FAILED=true
                shift
                ;;
            --help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$CSV_FILE" ]]; then
        echo "Error: --csv-file is required"
        usage
        exit 1
    fi

    if [[ ! -f "$CSV_FILE" ]]; then
        echo "Error: CSV file '$CSV_FILE' not found"
        exit 1
    fi
}

# Check and update ATX CLI version
check_atx_version() {
    log_info "Checking ATX CLI version..."
    
    local current_version
    current_version=$(atx --version 2>/dev/null || echo "unknown")
    log_info "Current ATX CLI version: $current_version"

    log_info "Checking for ATX CLI updates..."
    if atx update --check 2>/dev/null | grep -q "newer version"; then
        log_warning "A newer version of ATX CLI is available. Consider updating with 'atx update'"
    else
        log_success "ATX CLI is up to date"
    fi
}

# Setup environment
setup_environment() {
    # Set ATX_SHELL_TIMEOUT if not already set
    export ATX_SHELL_TIMEOUT=${ATX_SHELL_TIMEOUT:-$DEFAULT_SHELL_TIMEOUT}

    # Create output and clone directories first
    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$CLONE_DIR"
    
    # Clean up stale lock files from previous runs
    find "$OUTPUT_DIR" -name "*.lock" -type d -mmin +60 -exec rmdir {} \; 2>/dev/null || true
    
    # Check available disk space (require at least 1GB free)
    local available_space
    available_space=$(df -BG "$OUTPUT_DIR" | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $available_space -lt 1 ]]; then
        echo "Error: Insufficient disk space. At least 1GB required, found ${available_space}GB"
        exit 1
    fi
    
    # Initialize summary log
    echo "ATX CLI Batch Execution Summary - $(date)" > "$OUTPUT_DIR/summary.log"
    echo "=======================================" >> "$OUTPUT_DIR/summary.log"
    echo "" >> "$OUTPUT_DIR/summary.log"
    
    # Now we can safely log
    log_info "ATX_SHELL_TIMEOUT set to $ATX_SHELL_TIMEOUT seconds"
    log_info "Available disk space: ${available_space}GB"
}

# Detect repository type (git URL vs local path)
detect_repository_type() {
    local repo_path="$1"
    
    if [[ "$repo_path" =~ ^https?://.*\.git$ ]] || [[ "$repo_path" =~ ^https?://github\.com/ ]] || [[ "$repo_path" =~ ^https?://gitlab\.com/ ]]; then
        echo "https"
    elif [[ "$repo_path" =~ ^git@.*:.*\.git$ ]] || [[ "$repo_path" =~ ^git@github\.com: ]] || [[ "$repo_path" =~ ^git@gitlab\.com: ]]; then
        echo "ssh"
    else
        # Check if it's a local path (expand tilde first)
        local expanded_path
        expanded_path=$(eval echo "$repo_path")
        if [[ -d "$expanded_path" ]]; then
            echo "local"
        else
            echo "unknown"
        fi
    fi
}

# Normalize repository name from path or URL
normalize_repository_name() {
    local repo_path="$1"
    local repo_name
    
    if [[ "$repo_path" =~ ^https?:// ]] || [[ "$repo_path" =~ ^git@ ]]; then
        # Extract repo name from URL, handle various formats
        repo_name=$(basename "$repo_path" .git)
        repo_name=$(basename "$repo_name")
    else
        # Use directory name for local paths, expand ~ if needed
        repo_path=$(eval echo "$repo_path")
        repo_name=$(basename "$repo_path")
    fi
    
    # Sanitize name (remove special characters, keep alphanumeric, dash, underscore)
    repo_name=$(echo "$repo_name" | sed 's/[^a-zA-Z0-9._-]/_/g')
    echo "$repo_name"
}

# Validate repository path accessibility
validate_repository_path() {
    local repo_path="$1"
    local repo_type
    
    repo_type=$(detect_repository_type "$repo_path")
    
    case "$repo_type" in
        "local")
            # Expand tilde and validate directory exists
            local expanded_path
            expanded_path=$(eval echo "$repo_path")
            if [[ ! -d "$expanded_path" ]]; then
                return 1
            fi
            ;;
        "https"|"ssh")
            # For remote repos, we'll validate during clone
            return 0
            ;;
        "unknown")
            return 1
            ;;
    esac
    
    return 0
}

# Clone git repository with error handling
clone_repository() {
    local repo_url="$1"
    local clone_path="$2"
    local max_retries=2
    local retry_count=0
    local last_error=""
    
    # Remove existing clone if it exists
    if [[ -d "$clone_path" ]]; then
        rm -rf "$clone_path"
    fi
    
    # Validate git is available
    if ! command -v git &> /dev/null; then
        echo "Git is not installed or not in PATH" >&2
        return 1
    fi
    
    while [[ $retry_count -lt $max_retries ]]; do
        last_error=$(git clone --depth 1 "$repo_url" "$clone_path" 2>&1)
        if [[ $? -eq 0 ]]; then
            return 0
        fi
        
        retry_count=$((retry_count + 1))
        if [[ $retry_count -lt $max_retries ]]; then
            sleep 2
        fi
    done
    
    # Log specific error details
    echo "Git clone failed after $max_retries attempts: $last_error" >&2
    return 1
}

# Parse CSV file and validate entries
parse_csv() {
    local csv_file="$1"
    local temp_file="$OUTPUT_DIR/parsed_repos.txt"
    
    log_info "Parsing CSV file: $csv_file"
    
    # Skip header line and process CSV
    tail -n +2 "$csv_file" | while IFS=',' read -r repo_path build_cmd transform_name validation_cmds plan_context; do
        # Remove quotes and trim whitespace
        repo_path=$(echo "$repo_path" | sed 's/^"//;s/"$//' | xargs)
        build_cmd=$(echo "$build_cmd" | sed 's/^"//;s/"$//' | xargs)
        transform_name=$(echo "$transform_name" | sed 's/^"//;s/"$//' | xargs)
        validation_cmds=$(echo "$validation_cmds" | sed 's/^"//;s/"$//' | xargs)
        plan_context=$(echo "$plan_context" | sed 's/^"//;s/"$//' | xargs)
        
        # Skip empty lines
        [[ -z "$repo_path" ]] && continue
        
        # Validate repository path
        if ! validate_repository_path "$repo_path"; then
            log_error "Invalid repository path: $repo_path"
            continue
        fi
        
        # Generate normalized repo name
        local repo_name
        repo_name=$(normalize_repository_name "$repo_path")
        
        # Use defaults if CSV values are empty
        [[ -z "$build_cmd" ]] && build_cmd="$BUILD_COMMAND"
        
        # Validate required fields
        if [[ -z "$transform_name" ]]; then
            log_error "Missing transformation_name for repo: $repo_path"
            continue
        fi
        
        if [[ -z "$build_cmd" ]]; then
            log_error "Missing build_command for repo: $repo_path"
            continue
        fi
        
        echo "$repo_path|$repo_name|$build_cmd|$transform_name|$validation_cmds|$plan_context"
    done > "$temp_file"
    
    local repo_count
    repo_count=$(wc -l < "$temp_file")
    log_info "Found $repo_count valid repositories to process"
    
    if [[ $repo_count -eq 0 ]]; then
        log_error "No valid repositories found in CSV file"
        exit 1
    fi
}

# Clone or prepare repository
prepare_repository() {
    local repo_path="$1"
    local repo_name="$2"
    local repo_type
    
    repo_type=$(detect_repository_type "$repo_path")
    
    case "$repo_type" in
        "https"|"ssh")
            # It's a remote repository - clone it
            local clone_path="$CLONE_DIR/$repo_name"
            
            # Validate network connectivity for HTTPS repos
            if [[ "$repo_type" == "https" ]] && [[ "$repo_path" =~ github\.com ]]; then
                if ! ping -c 1 github.com >/dev/null 2>&1; then
                    echo "Network connectivity issue: Cannot reach github.com" >&2
                    return 1
                fi
            fi
            
            if clone_repository "$repo_path" "$clone_path" 2>&1; then
                # Validate the cloned repository has content
                if [[ ! -d "$clone_path" ]] || [[ -z "$(ls -A "$clone_path" 2>/dev/null)" ]]; then
                    echo "Cloned repository is empty or invalid: $clone_path" >&2
                    return 1
                fi
                echo "$clone_path"
            else
                echo "Failed to clone repository: $repo_path" >&2
                return 1
            fi
            ;;
        "local")
            # It's a local path - expand ~ and validate
            local expanded_path
            expanded_path=$(eval echo "$repo_path" 2>/dev/null)
            
            if [[ -z "$expanded_path" ]]; then
                echo "Invalid local path format: $repo_path" >&2
                return 1
            fi
            
            if [[ ! -d "$expanded_path" ]]; then
                echo "Local repository directory not found: $expanded_path" >&2
                return 1
            fi
            
            # Check if directory is readable
            if [[ ! -r "$expanded_path" ]]; then
                echo "Local repository directory not readable: $expanded_path" >&2
                return 1
            fi
            
            # Check if it looks like a code repository (has common files)
            if [[ ! -f "$expanded_path/pom.xml" ]] && [[ ! -f "$expanded_path/build.gradle" ]] && \
               [[ ! -f "$expanded_path/package.json" ]] && [[ ! -f "$expanded_path/Makefile" ]] && \
               [[ ! -f "$expanded_path/CMakeLists.txt" ]] && [[ ! -d "$expanded_path/src" ]]; then
                echo "Warning: Directory may not be a code repository: $expanded_path" >&2
            fi
            
            echo "$expanded_path"
            ;;
        "unknown")
            echo "Unknown or invalid repository type: $repo_path" >&2
            return 1
            ;;
        *)
            echo "Unsupported repository type '$repo_type' for: $repo_path" >&2
            return 1
            ;;
    esac
}

# Execute repositories in serial mode
execute_serial() {
    local temp_file="$OUTPUT_DIR/parsed_repos.txt"
    local total_repos
    local current_repo=0
    
    total_repos=$(wc -l < "$temp_file")
    log_info "Executing $total_repos repositories in serial mode"
    
    while IFS="|" read -r repo_path repo_name build_cmd transform_name validation_cmds plan_context; do
        current_repo=$((current_repo + 1))
        log_info "Processing repository $current_repo/$total_repos: $repo_name"
        
        # Store original CSV data for failed repos tracking
        echo "$repo_path|$build_cmd|$transform_name|$validation_cmds|$plan_context" >> "$OUTPUT_DIR/.repo_mapping_${repo_name}"
        
        execute_atx_for_repo "$repo_path" "$repo_name" "$build_cmd" "$transform_name" "$validation_cmds" "$plan_context"
    done < "$temp_file"
}

# Execute repositories in parallel mode
execute_parallel() {
    local temp_file="$OUTPUT_DIR/parsed_repos.txt"
    local total_repos
    local job_count=0
    local pids=()
    
    total_repos=$(wc -l < "$temp_file")
    log_info "Executing $total_repos repositories in parallel mode (max $MAX_PARALLEL_JOBS jobs)"
    
    while IFS="|" read -r repo_path repo_name build_cmd transform_name validation_cmds plan_context; do
        # Wait if we've reached max parallel jobs
        while [[ ${#pids[@]} -ge $MAX_PARALLEL_JOBS ]]; do
            wait_for_job_completion
        done
        
        log_info "Starting parallel job for repository: $repo_name"
        
        # Store original CSV data for failed repos tracking
        echo "$repo_path|$build_cmd|$transform_name|$validation_cmds|$plan_context" >> "$OUTPUT_DIR/.repo_mapping_${repo_name}"
        
        # Execute in background
        (
            execute_atx_for_repo "$repo_path" "$repo_name" "$build_cmd" "$transform_name" "$validation_cmds" "$plan_context"
        ) &
        
        local pid=$!
        pids+=($pid)
        job_count=$((job_count + 1))
        
        log_info "Started job $job_count/$total_repos (PID: $pid)"
    done < "$temp_file"
    
    # Wait for all remaining jobs to complete
    log_info "Waiting for all parallel jobs to complete..."
    for pid in "${pids[@]}"; do
        wait "$pid"
    done
    
    log_success "All parallel jobs completed"
}

# Wait for job completion in parallel mode
wait_for_job_completion() {
    local new_pids=()
    
    for pid in "${pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            new_pids+=($pid)
        else
            wait "$pid" 2>/dev/null || true
        fi
    done
    
    pids=("${new_pids[@]}")
    
    # If still at max capacity, sleep briefly
    if [[ ${#pids[@]} -ge $MAX_PARALLEL_JOBS ]]; then
        sleep 1
    fi
}

# Generate summary report with statistics table
generate_summary_report() {
    local total_duration="$1"
    local results_file="$OUTPUT_DIR/results.txt"
    
    log_info "Generating summary report..."
    
    # Count results
    local total_repos=0
    local successful_repos=0
    local failed_repos=0
    local total_exec_time=0
    
    # Skip header line and count results
    tail -n +2 "$results_file" | while IFS='|' read -r status repo_name message duration; do
        total_repos=$((total_repos + 1))
        total_exec_time=$((total_exec_time + duration))
        
        if [[ "$status" == "SUCCESS" ]]; then
            successful_repos=$((successful_repos + 1))
        else
            failed_repos=$((failed_repos + 1))
        fi
        
        # Store counts in temp files for main process
        echo "$total_repos" > "$OUTPUT_DIR/.total_count"
        echo "$successful_repos" > "$OUTPUT_DIR/.success_count"
        echo "$failed_repos" > "$OUTPUT_DIR/.failed_count"
        echo "$total_exec_time" > "$OUTPUT_DIR/.exec_time"
    done
    
    # Read counts from temp files
    total_repos=$(cat "$OUTPUT_DIR/.total_count" 2>/dev/null || echo "0")
    successful_repos=$(cat "$OUTPUT_DIR/.success_count" 2>/dev/null || echo "0")
    failed_repos=$(cat "$OUTPUT_DIR/.failed_count" 2>/dev/null || echo "0")
    total_exec_time=$(cat "$OUTPUT_DIR/.exec_time" 2>/dev/null || echo "0")
    
    # Calculate success rate
    local success_rate=0
    if [[ $total_repos -gt 0 ]]; then
        success_rate=$(( (successful_repos * 100) / total_repos ))
    fi
    
    # Generate summary report
    {
        echo ""
        echo "EXECUTION SUMMARY"
        echo "================="
        echo "Execution completed at: $(date)"
        echo "Total wall time: ${total_duration}s"
        echo "Total execution time: ${total_exec_time}s"
        echo ""
        echo "STATISTICS TABLE"
        echo "=================="
        printf "%-20s | %-10s\n" "Metric" "Value"
        printf "%-20s-+-%-10s\n" "--------------------" "----------"
        printf "%-20s | %-10s\n" "Total Repositories" "$total_repos"
        printf "%-20s | %-10s\n" "Successful" "$successful_repos"
        printf "%-20s | %-10s\n" "Failed" "$failed_repos"
        printf "%-20s | %-10s%%\n" "Success Rate" "$success_rate"
        printf "%-20s | %-10s\n" "Execution Mode" "$EXECUTION_MODE"
        printf "%-20s | %-10s\n" "Trust All Tools" "$TRUST_ALL_TOOLS"
        echo ""
        
        if [[ $failed_repos -gt 0 ]]; then
            echo "FAILED REPOSITORIES"
            echo "==================="
            tail -n +2 "$results_file" | while IFS='|' read -r status repo_name message duration; do
                if [[ "$status" == "FAILED" ]]; then
                    printf "%-30s | %s\n" "$repo_name" "$message"
                fi
            done
            echo ""
        fi
        
        echo "DETAILED RESULTS"
        echo "================"
        printf "%-10s | %-30s | %-40s | %-10s\n" "Status" "Repository" "Message" "Duration(s)"
        printf "%-10s-+-%-30s-+-%-40s-+-%-10s\n" "----------" "------------------------------" "----------------------------------------" "----------"
        tail -n +2 "$results_file" | while IFS='|' read -r status repo_name message duration; do
            printf "%-10s | %-30s | %-40s | %-10s\n" "$status" "$repo_name" "$message" "$duration"
        done
        echo ""
        
        echo "LOG FILES"
        echo "========="
        echo "Summary log: $OUTPUT_DIR/summary.log"
        echo "Individual logs: $OUTPUT_DIR/*_execution.log"
        echo "Results file: $OUTPUT_DIR/results.txt"
        if [[ $failed_repos -gt 0 ]]; then
            echo "Failed repos: $OUTPUT_DIR/failed_repos.csv"
        fi
        echo ""
        
    } >> "$OUTPUT_DIR/summary.log"
    
    # Create failed repos CSV for retry
    if [[ $failed_repos -gt 0 ]]; then
        echo "repo_path,build_command,transformation_name,validation_commands,additional_plan_context" > "$OUTPUT_DIR/failed_repos.csv"
        tail -n +2 "$results_file" | while IFS='|' read -r status repo_name message duration; do
            if [[ "$status" == "FAILED" ]]; then
                local mapping_file="$OUTPUT_DIR/.repo_mapping_${repo_name}"
                if [[ -f "$mapping_file" ]]; then
                    IFS='|' read -r repo_path build_cmd transform_name validation_cmds plan_context < "$mapping_file"
                    echo "\"$repo_path\",\"$build_cmd\",\"$transform_name\",\"$validation_cmds\",\"$plan_context\"" >> "$OUTPUT_DIR/failed_repos.csv"
                fi
            fi
        done
        log_info "Failed repositories list created: $OUTPUT_DIR/failed_repos.csv"
    fi
    
    # Clean up mapping files and temp config files
    rm -f "$OUTPUT_DIR/.repo_mapping_"*
    rm -f "$OUTPUT_DIR/"*_config.yaml
    
    # Clean up temp files
    rm -f "$OUTPUT_DIR/.total_count" "$OUTPUT_DIR/.success_count" "$OUTPUT_DIR/.failed_count" "$OUTPUT_DIR/.exec_time"
    
    # Display summary to console
    echo ""
    echo "=========================================="
    echo "BATCH EXECUTION COMPLETED"
    echo "=========================================="
    echo "Total repositories: $total_repos"
    echo "Successful: $successful_repos"
    echo "Failed: $failed_repos"
    echo "Success rate: ${success_rate}%"
    echo "Total time: ${total_duration}s"
    echo ""
    echo "Full summary available at: $OUTPUT_DIR/summary.log"
    echo "=========================================="
}

# Error handling and cleanup
cleanup() {
    local exit_code=$?
    log_info "Cleaning up..."
    
    # Kill any remaining background jobs
    if [[ ${#pids[@]} -gt 0 ]]; then
        log_info "Terminating remaining background jobs..."
        for pid in "${pids[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null || true
            fi
        done
    fi
    
    # Generate summary if results exist
    if [[ -f "$OUTPUT_DIR/results.txt" ]]; then
        local end_time=$(date +%s)
        local total_duration=$((end_time - start_time))
        generate_summary_report "$total_duration"
    fi
    
    exit $exit_code
}

# Signal handlers
handle_interrupt() {
    log_warning "Received interrupt signal. Cleaning up..."
    cleanup
}

# Set up signal handlers
trap handle_interrupt SIGINT SIGTERM

# Retry failed repositories
retry_failed_repos() {
    local failed_csv="$OUTPUT_DIR/failed_repos.csv"
    
    if [[ ! -f "$failed_csv" ]]; then
        log_error "No failed repositories file found: $failed_csv"
        return 1
    fi
    
    log_info "Retrying failed repositories from: $failed_csv"
    
    # Backup current results
    cp "$OUTPUT_DIR/results.txt" "$OUTPUT_DIR/results_backup_$(date +%s).txt"
    
    # Process failed repos
    CSV_FILE="$failed_csv"
    parse_csv "$CSV_FILE"
    
    # Append to existing results (don't overwrite)
    if [[ "$EXECUTION_MODE" == "serial" ]]; then
        execute_serial
    else
        execute_parallel
    fi
}

# Execute ATX CLI for a single repository
execute_atx_for_repo() {
    local repo_path="$1"
    local repo_name="$2"
    local build_cmd="$3"
    local transform_name="$4"
    local validation_cmds="$5"
    local plan_context="$6"
    
    local log_file="$OUTPUT_DIR/${repo_name}_execution.log"
    local start_time=$(date +%s)
    local retry_count=0
    
    # Prepare repository workspace with error handling
    local work_path
    local prep_error
    if ! prep_error=$(prepare_repository "$repo_path" "$repo_name" 2>&1); then
        echo "Repository preparation failed at $(date): $prep_error" >> "$log_file"
        write_with_lock "$OUTPUT_DIR/results.txt" "FAILED|$repo_name|Repository preparation failed: ${prep_error:0:50}...|0"
        return 1
    fi
    work_path="$prep_error"  # prepare_repository outputs the path on success
    
    # Retry loop for ATX execution
    while [[ $retry_count -le $MAX_RETRIES ]]; do
        # Create temporary configuration file if validation commands or additional plan context provided
        local config_file=""
        if [[ -n "$validation_cmds" ]] || [[ -n "$plan_context" ]]; then
            config_file="$OUTPUT_DIR/${repo_name}_config.yaml"
            {
                echo "codeRepositoryPath: \"$work_path\""
                echo "transformationName: \"$transform_name\""
                echo "buildCommand: \"$build_cmd\""
                if [[ -n "$validation_cmds" ]]; then
                    echo "validationCommands: >"
                    echo "  $validation_cmds"
                fi
                if [[ -n "$plan_context" ]]; then
                    echo "additionalPlanContext: >"
                    echo "  $plan_context"
                fi
            } > "$config_file"
        fi
        
        # Build ATX CLI command
        local atx_cmd="atx custom def exec"
        atx_cmd+=" --code-repository-path \"$work_path\""
        atx_cmd+=" --transformation-name \"$transform_name\""
        atx_cmd+=" --build-command \"$build_cmd\""
        
        if [[ "$TRUST_ALL_TOOLS" == true ]]; then
            atx_cmd+=" --trust-all-tools"
        fi
        
        if [[ -n "$config_file" ]]; then
            atx_cmd+=" --configuration file://$config_file"
        fi
        
        if [[ -n "$ADDITIONAL_PARAMS" ]]; then
            atx_cmd+=" $ADDITIONAL_PARAMS"
        fi
        
        if [[ "$DRY_RUN" == true ]]; then
            write_with_lock "$OUTPUT_DIR/results.txt" "SUCCESS|$repo_name|Dry run completed|0"
            return 0
        fi
        
        # Execute ATX CLI command with timeout and error handling
        echo "Starting ATX execution for $repo_name at $(date) (attempt $((retry_count + 1)))" >> "$log_file"
        echo "Command: $atx_cmd" >> "$log_file"
        echo "----------------------------------------" >> "$log_file"
        
        # Use timeout command if available
        local timeout_cmd=""
        if command -v timeout &> /dev/null; then
            timeout_cmd="timeout ${ATX_SHELL_TIMEOUT}"
        fi
        
        # Execute and capture exit code properly
        local exit_code=0
        if ! eval "$timeout_cmd $atx_cmd" >> "$log_file" 2>&1; then
            exit_code=$?
        fi
        
        if [[ $exit_code -eq 0 ]]; then
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            write_with_lock "$OUTPUT_DIR/results.txt" "SUCCESS|$repo_name|Transformation completed|$duration"
            return 0
        else
            retry_count=$((retry_count + 1))
            
            if [[ $exit_code -eq 124 ]]; then
                echo "Timeout occurred at $(date)" >> "$log_file"
            else
                echo "Execution failed with exit code $exit_code at $(date)" >> "$log_file"
            fi
            
            if [[ $retry_count -le $MAX_RETRIES ]]; then
                sleep 5  # Brief delay before retry
            fi
        fi
    done
    
    # All retries exhausted
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    write_with_lock "$OUTPUT_DIR/results.txt" "FAILED|$repo_name|Transformation failed after retries|$duration"
    return 1
}

# Main function
main() {
    # Global start time for cleanup
    start_time=$(date +%s)
    
    parse_args "$@"
    
    # Check ATX CLI exists before doing anything else
    if ! command -v atx &> /dev/null; then
        echo "Error: ATX CLI not found. Please install ATX CLI first."
        exit 1
    fi
    
    setup_environment
    check_atx_version
    
    log_info "Starting ATX CLI batch execution"
    log_info "CSV file: $CSV_FILE"
    log_info "Execution mode: $EXECUTION_MODE"
    log_info "Trust all tools: $TRUST_ALL_TOOLS"
    log_info "Output directory: $OUTPUT_DIR"
    log_info "Clone directory: $CLONE_DIR"
    
    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY RUN MODE - No actual execution will occur"
    fi

    # Handle retry mode
    if [[ "$RETRY_FAILED" == true ]]; then
        retry_failed_repos
        local end_time=$(date +%s)
        local total_duration=$((end_time - start_time))
        generate_summary_report "$total_duration"
        log_success "Retry execution completed successfully!"
        return 0
    fi

    # Parse CSV and prepare execution
    parse_csv "$CSV_FILE"
    
    # Initialize results file
    echo "STATUS|REPO_NAME|MESSAGE|DURATION" > "$OUTPUT_DIR/results.txt"
    
    # Execute based on mode
    if [[ "$EXECUTION_MODE" == "serial" ]]; then
        execute_serial
    else
        execute_parallel
    fi
    
    local end_time=$(date +%s)
    local total_duration=$((end_time - start_time))
    
    # Generate summary report
    generate_summary_report "$total_duration"
    
    log_success "Batch execution completed successfully!"
}

# Run main function with all arguments
main "$@"
