import os
import sys
import tarfile
import time
from datetime import datetime
from huggingface_hub import HfApi, hf_hub_download, list_repo_files, delete_file

api = HfApi()
repo_id = os.getenv("HF_DATASET")
token = os.getenv("HF_TOKEN")
BASE_PATH = "/root/.openclaw"

def log(message):
    """带时间戳的统一日志输出"""
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{now}] {message}")

def get_timestamp():
    return datetime.now().strftime("%Y%m%d_%H%M%S")

def restore():
    log("=== Starting Restore Process ===")
    try:
        if not repo_id or not token:
            log("[SKIP] Restore aborted: HF_DATASET or HF_TOKEN environment variables not found.")
            return
        
        log(f"Fetching file list from repo: {repo_id}...")
        all_files = list_repo_files(repo_id=repo_id, repo_type="dataset", token=token)
        backup_files = sorted([f for f in all_files if f.startswith("backup_") and f.endswith(".tar.gz")], reverse=True)
        
        if not backup_files:
            log("[NOTE] No existing backup files (.tar.gz) found in the repository.")
            return

        latest_file = backup_files[0]
        log(f"[ACTION] Found latest backup: {latest_file}. Starting download...")
        
        start_time = time.time()
        path = hf_hub_download(repo_id=repo_id, filename=latest_file, repo_type="dataset", token=token)
        download_duration = round(time.time() - start_time, 2)
        
        log(f"[DEBUG] Downloaded to cache in {download_duration}s. Extracting to {BASE_PATH}...")
        
        if not os.path.exists(BASE_PATH):
            os.makedirs(BASE_PATH)
            
        with tarfile.open(path, "r:gz") as tar:
            tar.extractall(path=BASE_PATH)
            
        log(f"[SUCCESS] Restore completed. All data synchronized to {BASE_PATH}")
        return True
    except Exception as e:
        log(f"[ERROR] Restore failed: {str(e)}")

def backup():
    log("=== Starting Scheduled Backup ===")
    local_filename = None
    try:
        if not repo_id or not token:
            log("[SKIP] Backup aborted: HF_DATASET or HF_TOKEN not set.")
            return
            
        if not os.path.exists(BASE_PATH):
            log(f"[SKIP] Backup aborted: Local directory {BASE_PATH} does not exist.")
            return

        # 生成文件名
        timestamp = get_timestamp()
        local_filename = f"backup_{timestamp}.tar.gz"

        log(f"[ACTION] Compressing data from {BASE_PATH}...")
        file_count = 0
        with tarfile.open(local_filename, "w:gz") as tar:
            for item in os.listdir(BASE_PATH):
                item_path = os.path.join(BASE_PATH, item)
                tar.add(item_path, arcname=item)
                file_count += 1
        
        log(f"[DEBUG] Packaging complete. {file_count} items compressed into {local_filename} ({round(os.path.getsize(local_filename)/1024, 2)} KB)")
        
        log(f"[ACTION] Uploading {local_filename} to Hugging Face...")
        api.upload_file(
            path_or_fileobj=local_filename,
            path_in_repo=local_filename,
            repo_id=repo_id,
            repo_type="dataset",
            token=token
        )
        log(f"[SUCCESS] Backup uploaded successfully: {local_filename}")

        # --- 清理逻辑 ---
        log("[CLEANUP] Checking for old backups (Retention: 12)...")
        all_files = list_repo_files(repo_id=repo_id, repo_type="dataset", token=token)
        backup_files = sorted([f for f in all_files if f.startswith("backup_") and f.endswith(".tar.gz")], reverse=True)
        
        if len(backup_files) > 12:
            old_files = backup_files[12:]
            log(f"[CLEANUP] Found {len(old_files)} redundant backups. Deleting...")
            for old_file in old_files:
                try:
                    delete_file(
                        path_in_repo=old_file,
                        repo_id=repo_id,
                        repo_type="dataset",
                        token=token
                    )
                    log(f"[CLEANUP] Deleted: {old_file}")
                except Exception as del_e:
                    log(f"[WARNING] Could not delete {old_file}: {del_e}")
        else:
            log("[CLEANUP] No old backups need to be removed.")

    except Exception as e:
        log(f"[ERROR] Backup failed: {str(e)}")
    finally:
        # 无论成功失败，都清理掉本地产生的临时文件，防止占满磁盘空间
        if local_filename and os.path.exists(local_filename):
            os.remove(local_filename)
            log(f"[DEBUG] Local temporary file {local_filename} removed.")

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "backup":
        backup()
    else:
        restore()
