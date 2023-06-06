import os
import shutil

def move_single_files(parent_dir):
    for folder_name in os.listdir(parent_dir):
        folder_path = os.path.join(parent_dir, folder_name)
        if os.path.isdir(folder_path):
            files = os.listdir(folder_path)
            if len(files) == 1 and os.path.isfile(os.path.join(folder_path, files[0])):
                file_to_move = os.path.join(folder_path, files[0])
                shutil.move(file_to_move, parent_dir)
                print(f"Moved {files[0]} from {folder_name} to {parent_dir}")

# Specify the parent directory
parent_directory = './'

# Call the function to move single files
move_single_files(parent_directory)
