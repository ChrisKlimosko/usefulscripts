import hashlib
import os

def get_file_hash(file_path, hash_algorithm='md5'):
    hash_algo = hashlib.new(hash_algorithm)
    with open(file_path, 'rb') as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hash_algo.update(chunk)
    return hash_algo.hexdigest()

def find_duplicates(directory, hash_algorithm='md5'):
    hashes = {}
    duplicates = []

    for root, _, files in os.walk(directory):
        for file in files:
            file_path = os.path.join(root, file)
            file_hash = get_file_hash(file_path, hash_algorithm)
            if file_hash in hashes:
                duplicates.append((file_path, hashes[file_hash]))
            else:
                hashes[file_hash] = file_path

    return duplicates

if __name__ == "__main__":
    directory = "./"
    hash_algorithm = "md5"
    duplicates = find_duplicates(directory, hash_algorithm)

    if duplicates:
        print("Found duplicates:")
        for dup in duplicates:
            print(f"Duplicate file: {dup[0]} and {dup[1]}")
    else:
        print("No duplicates found.")
