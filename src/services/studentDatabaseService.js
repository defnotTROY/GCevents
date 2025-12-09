/**
 * Student Database Service
 * 
 * This service is a placeholder for integrating with the external Student Data API.
 * It currently provides stub methods that can be expanded later.
 */

// Configuration for the Student Data API
const API_CONFIG = {
    baseUrl: '/api',
    apiKey: '2360351754b04ddc801e0ea0e74d176a35f201ad35dd1100af0bd025a12a91c8'
};

const studentDatabaseService = {

    /**
     * Fetch all students from the API
     * @returns {Promise<Array>}
     */
    async getAllStudents() {
        try {
            const response = await fetch(`${API_CONFIG.baseUrl}/students`, {
                headers: {
                    'x-api-key': API_CONFIG.apiKey,
                    'Content-Type': 'application/json'
                }
            });

            if (!response.ok) {
                throw new Error(`API Error: ${response.status}`);
            }

            const data = await response.json();
            return data.students || [];
        } catch (error) {
            console.error('[StudentDB] Fetch error:', error);
            return [];
        }
    },

    /**
     * Validates if a student exists by Email or ID (derived from email)
     * @param {string} identifier - Email or Student ID (9 digits)
     * @returns {Promise<{isValid: boolean, details: Object|null}>}
     */
    async validateStudent(identifier) {
        // Normalize identifier
        let searchEmail = identifier.toLowerCase();
        if (/^\d{9}$/.test(identifier)) {
            searchEmail = `${identifier}@gordoncollege.edu.ph`;
        }

        const students = await this.getAllStudents();
        const student = students.find(s => s.email.toLowerCase() === searchEmail);

        return {
            isValid: !!student,
            details: student || null
        };
    },

    /**
     * Retrieves student information by ID or Email
     * @param {string} identifier 
     * @returns {Promise<Object|null>}
     */
    /**
     * Retrieves student information by ID or Email
     * @param {string} identifier 
     * @returns {Promise<Object|null>}
     */
    async getStudentInfo(identifier) {
        const { details } = await this.validateStudent(identifier);
        return details;
    },

    /**
     * Verify student credentials against the external API
     * @param {string} identifier - Email or Student ID
     * @param {string} password - Password to check
     * @returns {Promise<Object|null>} Student object if valid, null otherwise
     */
    async verifyCredentials(identifier, password) {
        const { details } = await this.validateStudent(identifier);

        if (details && details.password === password) {
            return details;
        }

        return null;
    }
};

export default studentDatabaseService;
