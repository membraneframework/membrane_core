import os

def concatenate_files(dir_path, output_file):
    """
    Concatenates the content of all text files located in the directory and sub-directories.
    
    :param dir_path: String, path of the directory to search for files to concatenate.
    :param output_file: String, path of the file where all content will be saved.
    """
    with open(output_file, 'w') as outfile:  # Opening the file that will hold all the contents.
        for root, dirs, files in os.walk(dir_path):  # Traversing directory tree.
            print(files)
            for filename in files:
                filepath = os.path.join(root, filename)  # Creating full path to the file.
                try:
                    with open(filepath, 'r') as readfile:  # Opening each file safely with 'with'.
                        content = readfile.read()
                        outfile.write("Content of " + filepath + ":\n" + content + "\n")  # Writing content followed by a newline.
                except Exception as e:
                    print(f"Failed to read file {filepath}: {e}")

# Usage
# directory_path = '~/membrane/membrane_core'  # Set your directory path here.
directory_path = os.getcwd() + "/lib"
output_path = 'combined_output.txt'
concatenate_files(directory_path, output_path)

print(f"All files have been concatenated into {output_path}.")