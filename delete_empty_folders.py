import os

def delete_empty_folders(parent_dir):
    for folder_name in os.listdir(parent_dir):
        folder_path = os.path.join(parent_dir, folder_name)
        if os.path.isdir(folder_path):
            if not os.listdir(folder_path):  # Check if folder is empty
                os.rmdir(folder_path)
                print(f"Deleted empty folder: {folder_path}")

# Specify the parent directory
parent_directory = './'

# Call the function to delete empty folders
delete_empty_folders(parent_directory)
